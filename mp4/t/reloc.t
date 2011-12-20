#!perl

use strict;
use warnings;

use BBC::HDS::MP4::Relocator;
use Data::Dumper;

use Test::More tests => 10_000;

test_reloc( infiberator( 0, 1, 1 ), 10_000 );

sub test_reloc {
  my ( $iter, $max ) = @_;

  my @ref   = map { [ $_, $_ ] } 0 .. $max - 1;
  my $dist  = 0;
  my $dir   = 1;
  my @reloc = ();

  while ( 1 ) {
    my ( $sz, $pos ) = $iter->();
    last if $pos >= $max;

    my $end  = $pos + $sz;
    my $disp = $dist * $dir;

    $ref[$_][1] += $disp for $pos .. $end - 1;

    push @reloc, [ $pos, $end, $disp ];

    $dist++;
    $dir *= -1;
  }

  my $r = BBC::HDS::MP4::Relocator->new( @reloc );

  for my $d ( @ref ) {
    my $got = $r->reloc( $d->[0] );
    is $got, $d->[1], "$d->[0] --> $d->[1]";
  }
}

sub infiberator {
  my @fib = @_;
  return sub {
    push @fib, $fib[-1] + $fib[-2];
    return ( shift( @fib ), $fib[-1] );
  };
}

# vim:ts=2:sw=2:et:ft=perl

