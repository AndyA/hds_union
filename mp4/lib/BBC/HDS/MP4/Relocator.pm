package BBC::HDS::MP4::Relocator;

use strict;
use warnings;

use Carp qw( croak );

=head1 NAME

BBC::HDS::MP4::Relocator - Relocate references to data that's moved

=cut

sub new {
  my ( $class, @reloc ) = @_;
  return bless { reloc => [ sort { $a->[0] <=> $b->[0] } @reloc ] }, $class;
}

sub reloc {
  my ( $self, $src ) = @_;

  my $r = $self->{reloc};
  my ( $lo, $hi ) = ( 0, scalar @$r );
  while ( $lo < $hi ) {
    my $mid = int( ( $lo + $hi ) / 2 );
    if ( $src < $r->[$mid][0] ) {
      $hi = $mid;
    }
    elsif ( $src >= $r->[$mid][1] ) {
      $lo = $mid + 1;
    }
    else {
      return $src + $r->[$mid][2];
    }
  }

  return $src;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
