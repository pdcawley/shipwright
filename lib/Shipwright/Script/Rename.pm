package Shipwright::Script::Rename;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/repository log_level log_file name new_name/);

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'name=s'         => 'name',
        'new-name=s'     => 'new_name',
    );
}

sub run {
    my $self = shift;

    my ( $name, $new_name ) = ( $self->name, $self->new_name );

    $name = shift unless $name;
    $new_name = shift unless $new_name;

    $self->name( $name );
    $self->new_name( $new_name );

    die 'need name arg' unless $name;
    die 'need new-name arg' unless $new_name;

    die "invalid new-name: $new_name, should only contain - and alphanumeric"
      unless $new_name =~ /^[-\w]+$/;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
    );

    my $order = $shipwright->backend->order;

    die "no such dist: $name" unless grep { $_ eq $name } @$order;

    $shipwright->backend->move(
        path     => "dists/$name",
        new_path => "dists/$new_name",
    );
    $shipwright->backend->move(
        path     => "scripts/$name",
        new_path => "scripts/$new_name",
    );

    # update order.yml
    @$order = map { $_ eq $name ? $new_name : $_ } @$order;
    $shipwright->backend->order($order);

    # update map.yml
    my $map = $shipwright->backend->map || {};
    for ( keys %$map ) {
        $map->{$_} = $new_name if $map->{$_} eq $name;
    }
    $shipwright->backend->map($map);

    # update version.yml, source.yml and flags.yml
    my $version = $shipwright->backend->version || {};
    my $source  = $shipwright->backend->source  || {};
    my $flags   = $shipwright->backend->flags   || {};

    $self->_update_hash( $source, $flags, $version );

    $shipwright->backend->version($version);
    $shipwright->backend->source($source);
    $shipwright->backend->flags($flags);

    print "renamed $name to $new_name with success\n";
}

sub _update_hash {
    my $self     = shift;
    my @hashrefs = @_;
    my $name     = $self->name;
    my $new_name = $self->new_name;

    for my $hashref (@hashrefs) {
        for ( keys %$hashref ) {
            if ( $_ eq $name ) {
                $hashref->{$new_name} = delete $hashref->{$_};
                last;
            }
        }
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Rename - Rename a dist

=head1 SYNOPSIS

  shipwright rename          rename a source

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --name NAME                  : specify the dist to be renamed
 --new-name NAME              : specify the new dist name
