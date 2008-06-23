package Shipwright::Script::Update;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level name all follow log_file builder utility/);

use Shipwright;
use File::Spec;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;
use Hash::Merge;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'name=s'         => 'name',
        'a|all'          => 'all',
        'follow'         => 'follow',
        'builder'        => 'builder',
        'utility'        => 'utility',
    );
}

my ( $shipwright, $map, $source );

sub run {
    my $self = shift;
    my $name = shift;

    $shipwright = Shipwright->new(
        repository => $self->repository,
    );

    if ( $self->builder ) {
        $shipwright->backend->update(
            path => File::Spec->catfile( 'bin', 'shipwright-builder' ) );
    }
    elsif ( $self->utility ) {
        $shipwright->backend->update(
            path => File::Spec->catfile( 'bin', 'shipwright-utility' ) );

    }
    else {

        $self->name($name) if $name && !$self->name;

        die 'need name arg' unless $self->name || $self->all;

        $map    = $shipwright->backend->map    || {};
        $source = $shipwright->backend->source || {};

        if ( $self->all ) {
            my $dists = $shipwright->backend->order || [];
            for (@$dists) {
                $self->_update($_);
            }
        }
        else {
            if ( !$source->{ $self->name } && $map->{ $self->name } ) {

                # in case the name is module name
                $self->name( $map->{ $self->name } );
            }

            my @dists;
            if ( $self->follow ) {
                my (%checked);
                my $find_deps;
                $find_deps = sub {
                    my $name = shift;

                    return if $checked{$name}++;    # we've checked this $name

                    my ($require) =
                      $shipwright->backend->requires( name => $name );
                    for my $type (qw/requires build_requires recommends/) {
                        for ( keys %{ $require->{$type} } ) {
                            $find_deps->($_);
                        }
                    }
                };

                $find_deps->( $self->name );
                @dists = keys %checked;
            }
            for ( @dists, $self->name ) {
                $self->_update($_);
            }
        }
    }

    print "updated with success\n";
}

sub _update {
    my $self = shift;
    my $name = shift;

    if ( $source->{$name} ) {
        $shipwright->source(
            Shipwright::Source->new(
                name   => $name,
                source => $source->{$name},
                follow => 0,
            )
        );
    }
    else {

        # it's a cpan dist
        my $s;

        if ( $name =~ /^cpan-/ ) {
            $s = { reverse %$map }->{$name};
        }
        elsif ( $map->{$name} ) {
            $s    = $name;
            $name = $map->{$name};
        }
        else {
            die 'invalid name ' . $name;
        }

        $shipwright->source(
            Shipwright::Source->new(
                source => "cpan:$s",
                follow => 0,
            )
        );
    }

    $shipwright->source->run;

    my $version =
      Shipwright::Util::LoadFile( $shipwright->source->version_path );

    $shipwright->backend->import(
        source  => File::Spec->catfile( $shipwright->source->directory, $name ),
        comment => "update $name",
        overwrite => 1,
        version   => $version->{$name},
    );

}

1;

__END__

=head1 NAME

Shipwright::Script::Update - Update dist(s) and scripts

=head1 SYNOPSIS

 update --all
 update --name [dist] [--follow]
 update --builder
 update --utility

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --name NAME                  : specify the name of the project
 --all                        : update all dists
 --follow                     : update one dist with all its dependencies
 --builder                    : update bin/shipwright-builder
 --utility                    : update bin/shipwright-utility

=head1 DESCRIPTION

The update command updates one or multiple svk, svn, or CPAN dists in a
shipwright repository to the latest version. Only the source in F<dists/>
will be updated. To update other types of sources, you must re-import the new
version, using the same name in order to overwrite. The C<import> command will
also re-generate files in F<scripts/> (see L<Shipwright::Import> for more
information).

The update command can also be used to update a repository's builder or utility
script to the version shipped with the Shipwright dist on your system, by
specifying the C<--builder> or C<--utility> options.

=head1 ALIASES

up
