package Shipwright::Script::Build;

use warnings;
use strict;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level install_base build_base skip skip_test only_test
      force log_file flags name perl only/
);

use Shipwright;
use Cwd 'abs_path';

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'install-base=s' => 'install_base',
        'build-base=s'   => 'build_base',
        'name=s'         => 'name',
        'skip=s'         => 'skip',
        'only=s'         => 'only',
        'flags=s'        => 'flags',
        'skip-test'      => 'skip_test',
        'only-test'      => 'only_test',
        'force'          => 'force',
        'perl'           => 'perl',
    );
}

sub run {
    my $self         = shift;
    my $install_base = shift;
    $self->install_base($install_base)
      if $install_base && !$self->install_base;

    if ( $self->install_base ) {

        # convert relative path to be absolute
        $self->install_base( abs_path( $self->install_base ) );
    }

    unless ( $self->name ) {
        if ( $self->repository =~ m{([-.\w]+)/([.\d]+)$} ) {
            $self->name("$1-$2");
        }
        elsif ( $self->repository =~ /([-.\w]+)$/ ) {
            $self->name($1);
        }
    }

    $self->skip( { map { $_ => 1 } split /\s*,\s*/, $self->skip || '' } );

    if ( $self->only ) {
        $self->only( { map { $_ => 1 } split /\s*,\s*/, $self->only } );
    }

    $self->flags(
        {
            default => 1,
            map { $_ => 1 } split /\s*,\s*/, $self->flags || ''
        }
    );

    my $shipwright = Shipwright->new(
        map { $_ => $self->$_ }
          qw/repository log_level log_file skip skip_test
          flags name force only_test install_base build_base perl only/
    );

    $shipwright->backend->export( target => $shipwright->build->build_base );
    $shipwright->build->run();
}

1;

__END__

=head1 NAME

Shipwright::Script::Build - build the specified project

=head1 SYNOPSIS

  shipwright build           build a project

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --log-file         specify the log file
   --install-base     specify install base. default is an autocreated temp dir
   --skip             specify dists which'll be skipped
   --only             specify dists which'll be installed only
   --skip-test        specify whether to skip test
   --only-test        just test(the running script is t/test)
   --flags            specify flags
   --name             specify the name of the project
   --perl             specify the path of perl that run the cmds in scripts/

