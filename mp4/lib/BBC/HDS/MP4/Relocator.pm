package BBC::HDS::MP4::Relocator;

use strict;
use warnings;

use Carp qw( croak );

=head1 NAME

BBC::HDS::MP4::Relocator - Relocate references to data that's moved

=cut

sub new {
  my $class = shift;
  my @rel = sort { $a->[0] <=> $b->[0] } @_;
  $class->_check( \@rel );
  return bless { reloc => \@rel }, $class;
}

sub _check {
  my ( $class, $rel ) = @_;
  for my $i ( 1 .. $#$rel ) {
    croak "Overlap in relocation list"
     if $rel->[ $i - 1 ][1] > $rel->[$i][0];
  }
}

sub reloc {
  my ( $self, @src ) = @_;
  return map { $self->_reloc( $_ ) } @src if wantarray;
  return $self->_reloc( @src );
}

sub _reloc {
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

  croak "No relocation for $src";
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
