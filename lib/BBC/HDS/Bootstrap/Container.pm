package BBC::HDS::Bootstrap::Container;

use strict;
use warnings;

use BBC::HDS::Bootstrap::Box;

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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
