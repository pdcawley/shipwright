package Shipwright::Script::Defaultbranch;
use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;

use Shipwright;

sub run {
    my $self    = shift;
    my $name    = shift;
    my $default = shift;

    confess "need name arg\n"    unless $name;
    confess "need default arg\n" unless $default;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    my $branches = $shipwright->backend->branches;

    if ( grep { $default eq $_ } @{ $branches->{$name} } ) {

        # move $default to head
        @{ $branches->{$name} } =
          ( $default, grep { $_ ne $default } @{ $branches->{$name} } );
        $shipwright->backend->branches($branches);
        $self->log->fatal(
            "set default branch for $name with success, now it's $default");
    }
    else {
        confess "$name doesn't have branches $default.
Available branches are " . join( ', ', @{ $branches->{$name} } ) . "\n";
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Defaultbranch - Set the default branch for a dist

=head1 SYNOPSIS

 defaultbranch -r ... DIST BRANCH

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file

=head1 DESCRIPTION

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

