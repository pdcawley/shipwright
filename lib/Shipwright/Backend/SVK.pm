package Shipwright::Backend::SVK;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile/;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Shipwright::Backend::Base/;

=head1 NAME

Shipwright::Backend::SVK - SVK repository backend

=head1 DESCRIPTION

This module implements an SVK repository backend for Shipwright.

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
        _initialize => 1,
        comment     => 'created project',
    );
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

    my @cmd;

    if ( $type eq 'checkout' ) {
        if ( $args{detach} ) {
            @cmd = [ 'svk', 'checkout', '-d', $args{target} ];
        }
        else {
            @cmd = [
                'svk',                           'checkout',
                $self->repository . $args{path}, $args{target}
            ];
        }
    }
    elsif ( $type eq 'export' ) {
        @cmd = (
            [
                'svk',                           'checkout',
                $self->repository . $args{path}, $args{target}
            ],
            [ 'svk', 'checkout', '-d', $args{target} ]
        );
    }
    elsif ( $type eq 'list' ) {
        @cmd = [ 'svk', 'list', $self->repository . $args{path} ];
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_initialize} ) {
            @cmd = [
                'svk',         'import',
                $args{source}, $self->repository,
                '-m',          $args{comment},
            ];
        }
        elsif ( $args{_extra_tests} ) {
            @cmd = [
                'svk',         'import',
                $args{source}, $self->repository . '/t/extra',
                '-m',          $args{comment},
            ];
        }
        else {
            my ( $path, $source );
            if ( $args{build_script} ) {
                $path   = "/scripts/$args{name}";
                $source = $args{build_script};
            }
            else {
                $path =
                  $self->has_branch_support
                  ? "/sources/$args{name}/$args{as}"
                  : "/dists/$args{name}";
                $source = $args{source};
            }

            if ( $self->info( path => $path ) ) {
                my $tmp_dir =
                  tempdir( 'shipwright_backend_svk_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
                @cmd = (
                    [ 'rm', '-rf', "$tmp_dir" ],
                    [ 'svk', 'checkout', $self->repository . $path, $tmp_dir ],
                    [ 'rm',  '-rf',      "$tmp_dir" ],
                    [ 'cp', '-r', $source, "$tmp_dir" ],
                    [
                        'svk',      'commit',
                        '--import', $tmp_dir,
                        '-m',       $args{comment}
                    ],
                    [ 'svk', 'checkout', '-d', $tmp_dir ],
                );
            }
            else {
                @cmd = [
                    'svk',   'import',
                    $source, $self->repository . $path,
                    '-m',    $args{comment},
                ];
            }
        }
    }
    elsif ( $type eq 'commit' ) {
        @cmd =
          [ 'svk', 'commit', '-m', $args{comment}, $args{path} ];
    }
    elsif ( $type eq 'delete' ) {
        @cmd = [
            'svk', 'delete', '-m',
            'delete repository',
            $self->repository . $args{path},
        ];
    }
    elsif ( $type eq 'move' ) {
        @cmd = [
            'svk',
            'move',
            '-m',
            "move $args{path} to $args{new_path}",
            $self->repository . $args{path},
            $self->repository . $args{new_path}
        ];
    }
    elsif ( $type eq 'info' ) {
        @cmd = [ 'svk', 'info', $self->repository . $args{path} ];
    }
    elsif ( $type eq 'cat' ) {
        @cmd = [ 'svk', 'cat', $self->repository . $args{path} ];
    }
    else {
        croak "invalid command: $type";
    }

    return @cmd;
}

sub _yml {
    my $self = shift;
    my $path = shift;
    my $yml  = shift;

    $path = '/' . $path unless $path =~ m{^/};

    my ($f) = $path =~ m{.*/(.*)$};

    if ($yml) {
        my $dir =
          tempdir( 'shipwright_backend_svk_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
        my $file = catfile( $dir, $f );

        $self->checkout( path => $path, target => $file );

        Shipwright::Util::DumpFile( $file, $yml );
        $self->commit( path => $file, comment => "updated $path" );
        $self->checkout( detach => 1, target => $file );
    }
    else {
        my ($out) =
          Shipwright::Util->run( [ 'svk', 'cat', $self->repository . $path ] );
        return Shipwright::Util::Load($out);
    }
}

=item info

A wrapper around svk's info command.

=cut

sub info {
    my $self = shift;
    my ( $info, $err ) = $self->SUPER::info(@_);

    if (wantarray) {
        return $info, $err;
    }
    else {
        return if $info =~ /not exist|not a checkout path/;
        return $info;
    }
}

=item check_repository

Check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    my %args = @_;

    if ( $args{action} eq 'create' ) {

        # svk always has //
        return 1 if $self->repository =~ m{^//};

        if ( $self->repository =~ m{^(/[^/]+/)} ) {
            my $ori = $self->repository;
            $self->repository($1);

            my $info = $self->info;

            # revert back
            $self->repository($ori);

            return 1 if $info;
        }

    }
    else {
        return $self->SUPER::check_repository(@_);
    }
    return;
}

sub _update_file {
    my $self   = shift;
    my $path   = shift;
    my $latest = shift;

    my $dir =
      tempdir( 'shipwright_backend_svk_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    my $file = catfile( $dir, $path );

    $self->checkout(
        path   => $path,
        target => $file,
    );

    copy( $latest, $file );
    $self->commit(
        path    => $file,
        comment => "updated $path",
    );
    $self->checkout( detach => 1, target => $file );
}

=back

=cut

1;
