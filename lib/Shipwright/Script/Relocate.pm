package Shipwright::Script::Relocate;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

__PACKAGE__->mk_accessors('as');

sub options {
    ( 'as=s' => 'as', );
}

use Shipwright;

sub run {
    my $self = shift;
    my ( $name, $new_source ) = @_;

    confess "need name arg"   unless $name;
    confess "need source arg" unless $new_source;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        source     => $new_source,
    );

    my $source   = $shipwright->backend->source;
    my $branches = $shipwright->backend->branches;

    # die if the specified branch doesn't exist
    if ( $branches && $self->as ) {
        confess "$name doesn't have branch "
          . $self->as
          . ". please use import cmd instead"
          unless grep { $_ eq $self->as } @{ $branches->{$name} || [] };
    }

    if ( exists $source->{$name} ) {
        if (
            (
                ref $source->{$name}
                  && $source->{$name}{ $self->as || $branches->{$name}[0] } eq
                  $new_source
            )
            || $source->{$name} eq $new_source
          )
        {
            print "the new source is the same as old source, won't update\n";
        }
        else {
            if ( ref $source->{$name} ) {
                $source->{$name} = {
                    %{ $source->{$name} },
                    $self->as || $branches->{$name}[0] => $new_source
                };
            }
            else {
                $source->{$name} = $new_source;
            }

            $shipwright->backend->source($source);
            print "relocated $name to $new_source with success\n";
        }
    }
    else {
        print "haven't found $name in source.yml, won't relocate\n";
    }

}

1;

__END__

=head1 NAME

Shipwright::Script::Relocate - Relocate source of a dist(not cpan)

=head1 SYNOPSIS

 relocate NAME SOURCE

=head1 OPTIONS
   -r [--repository] REPOSITORY    : specify the repository of our project
   -l [--log-level] LOGLEVEL       : specify the log level
   --log-file FILENAME             : specify the log file
                                     (info, debug, warn, error, or fatal)
   NAME                            : sepecify the dist name
   SOURCE                          : specify the new source
