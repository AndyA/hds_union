package BBC::HDS::Bootstrap::Container;

use strict;
use warnings;

use BBC::HDS::Bootstrap::Box;
use Carp qw( croak );

=head1 NAME

BBC::HDS::Bootstrap::Container - Container for bootstrap objects

=cut

sub index { {} }

sub box {
  my ( $self, $name, $index ) = @_;
  my $idx = $self->index;
  return unless $idx->{$name};
  return BBC::HDS::Bootstrap::Box->create(
    $idx->{$name}[ $index || 0 ] );
}

sub can {
  my ( $self, $method ) = @_;
  return $self->SUPER::can( $method )
   || $self->_make_accessor( $method );
}

sub _make_accessor {
  my ( $self, $method ) = @_;
  return unless ref $self;
  my $data = $self->data;
  return
   unless $data
     && 'HASH' eq ref $data
     && exists $data->{$method};
  return sub { $data->{$method} };
}

sub AUTOLOAD {
  my $self = shift;

  my $type = ref( $self )
   or croak "$self is not an object";

  my $name = our $AUTOLOAD;
  $name =~ s/.*://;    # strip fully-qualified portion

  my $ac = $self->can( $name )
   or croak "Can't access `$name' field in class $type";

  return $ac->();
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
