package BBC::HDS::MP4::IOBase;

use strict;
use warnings;
use Carp qw( croak );

=head1 NAME

BBC::HDS::MP4::IOBase - Base class for MP4 IO

=cut

sub _whence_to_pos {
  my ( $self, $distance, $whence ) = @_;
  my $base
   = $whence == 0 ? 0
   : $whence == 1 ? $self->tell
   : $whence == 2 ? $self->size
   :                croak "Bad whence value";
  return $base + $distance;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
