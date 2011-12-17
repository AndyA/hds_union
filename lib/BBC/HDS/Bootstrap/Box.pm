package BBC::HDS::Bootstrap::Box;

use strict;
use warnings;

use Carp qw( croak );

use base qw( BBC::HDS::Bootstrap::Container );

=head1 NAME

BBC::HDS::Bootstrap::Box - A box

=cut

use accessors::ro qw( data );

sub create {
  my ( $class, $box, @args ) = @_;
  return unless $box;
  my $clazz = $class->_subclass_for( $box );
  my $self = bless { data => $box }, $clazz;
  $self->_init( @args );
  return $self;
}

sub _init { }

sub _subclass_for {
  my ( $class, $box ) = @_;
  ( my $type = $box->{bi}{type} ) =~ s/\s+//g;
  croak "Bad box type: $type" unless $type =~ /^\w+$/;
  my $clazz = join '::', __PACKAGE__, $type;
  eval "use $clazz";
  croak $@ if $@;
  return $clazz;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
