package Shipwright::Backend::SVN;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;

our %REQUIRE_OPTIONS = ( import => [qw/source/], );

use base qw/Shipwright::Backend::Base/;

=head1 NAME

Shipwright::Backend::SVN - SVN repository backend

=head1 DESCRIPTION

This module implements a SVN repository backend for Shipwright.

=head1 METHODS

=over

=item initialize

Initialize a project.

=cut

sub initialize {
    my $self = shift;
    my $dir  = $self->SUPER::initialize(@_);

    $self->delete;    # clean repository in case it exists
    $self->import(
        source      => $dir,
        comment     => 'create project',
        _initialize => 1,
    );

}

=item import

=cut

sub import {
    my $self = shift;
    return unless @_;
    return $self->SUPER::import( @_, delete => 1 );
}

# a cmd generating factory
sub _cmd {
    my $self = shift;
    my $type = shift;
    my %args = @_;
    $args{path}    ||= '';
    $args{comment} ||= '';

    for ( @{ $REQUIRE_OPTIONS{$type} } ) {
        croak "$type need option $_" unless $args{$_};
    }

    my $cmd;

    if ( $type eq 'checkout' ) {
        $cmd =
          [ 'svn', 'checkout', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'export' ) {
        $cmd =
          [ 'svn', 'export', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_initialize} ) {
            $cmd = [
                'svn',         'import',
                $args{source}, $self->repository,
                '-m',          q{'} . $args{comment} . q{'}
            ];
        }
        elsif ( $args{_extra_tests} ) {
            $cmd = [
                'svn', 'import',
                $args{source}, join( '/', $self->repository, 't', 'extra' ),
                '-m', q{'} . $args{comment} . q{'},
            ];
        }
        else {
            if ( my $script_dir = $args{build_script} ) {
                $cmd = [
                    'svn',       'import',
                    $script_dir, $self->repository . "/scripts/$args{name}/",
                    '-m',        q{'} . $args{comment} || '' . q{'},
                ];
            }
            else {
                $cmd = [
                    'svn',         'import',
                    $args{source}, $self->repository . "/dists/$args{name}",
                    '-m',          q{'} . $args{comment} . q{'},
                ];
            }
        }
    }
    elsif ( $type eq 'list' ) {
        $cmd = [ 'svn', 'list', $self->repository . $args{path} ];
    }
    elsif ( $type eq 'commit' ) {
        $cmd =
          [ 'svn', 'commit', '-m', q{'} . $args{comment} . q{'}, $args{path} ];
    }
    elsif ( $type eq 'delete' ) {
        $cmd = [
            'svn', 'delete', '-m', q{'} . 'delete' . $args{path} . q{'},
            join '/', $self->repository, $args{path}
        ];
    }
    elsif ( $type eq 'move' ) {
        $cmd = [
            'svn',
            'move',
            '-m',
            q{'} . "move $args{path} to $args{new_path}" . q{'},
            join( '/', $self->repository, $args{path} ),
            join( '/', $self->repository, $args{new_path} )
        ];
    }
    elsif ( $type eq 'info' ) {
        $cmd = [ 'svn', 'info', join '/', $self->repository, $args{path} ];
    }
    elsif ( $type eq 'propset' ) {
        $cmd = [
            'svn',       'propset',
            $args{type}, q{'} . $args{value} . q{'},
            $args{path}
        ];
    }
    else {
        croak "invalid command: $type";
    }

    return $cmd;
}

sub _yml {
    my $self = shift;
    my $path = shift;
    my $yml  = shift;

    $path = '/' . $path unless $path =~ m{^/};

    my ( $p_dir, $f );
    if ( $path =~ m{(.*)/(.*)$} ) {
        $p_dir = $1;
        $f     = $2;
    }

    if ($yml) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, $f );

        $self->checkout(
            path   => $p_dir,
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $yml );
        $self->commit( path => $file, comment => "updated $path" );
    }
    else {
        my ($out) =
          Shipwright::Util->run( [ 'svn', 'cat', $self->repository . $path ] );
        return Shipwright::Util::Load($out);
    }
}

=item info

A wrapper around svn's info command.

=cut

sub info {
    my $self = shift;
    my ( $info, $err ) = $self->SUPER::info(@_);

    if (wantarray) {
        return $info, $err;
    }
    else {
        if ($err) {
            $err =~ s/\s+$//;
            $self->log->warn($err);
            return;
        }
        return $info;
    }
}

=item propset

A wrapper around svn's propset command.

=cut

sub propset {
    my $self = shift;
    my %args = @_;
    my $dir  = tempdir( CLEANUP => 1 );

    $self->checkout( target => $dir, );
    Shipwright::Util->run(
        $self->_cmd(
            propset => %args,
            path => File::Spec->catfile( $dir, $args{path} )
        )
    );

    $self->commit(
        path    => File::Spec->catfile( $dir, $args{path} ),
        comment => "set prop $args{type}"
    );
}

=item test_script

Set test_script for a project, i.e. update the t/test script.

=cut

sub test_script {
    my $self   = shift;
    my %args   = @_;
    my $script = $args{source};
    croak 'need source option' unless $script;

    my $dir = tempdir( CLEANUP => 1 );

    $self->checkout(
        path   => '/t',
        target => $dir,
    );

    my $file = File::Spec->catfile( $dir, 'test' );

    copy( $args{source}, $file );
    $self->commit( path => $file, comment => "update test script" );
}

=item check_repository

Check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    my %args = @_;

    if ( $args{action} eq 'create' ) {

        my ( $info, $err ) = $self->info;

        return 1 if $info || $err && $err =~ /Not a valid URL/;

    }
    else {
        return $self->SUPER::check_repository(@_);
    }
    return;
}

=item update

Update shipwright's own files, e.g. bin/shipwright-builder.

=cut

sub update {
    my $self   = shift;
    my %args   = @_;
    my $latest = $self->SUPER::update(@_);

    if ( $args{path} =~ m{(.*)/} ) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, $args{path} );

        $self->checkout(
            path   => $1,
            target => $dir,
        );

        copy( $latest, $file );
        $self->commit(
            path    => $file,
            comment => "update $args{path}",
        );
    }
}

=back

=cut

1;
