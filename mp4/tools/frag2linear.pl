#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use List::Util qw( max );

use lib qw( lib );

use BBC::HDS::MP4::Reader;
use BBC::HDS::MP4::Writer;

my $src = shift @ARGV;
my $root = BBC::HDS::MP4::Reader->parse( $src, my $data = {} );
report( $data );
if ( @ARGV ) {
  my $dst = shift @ARGV;
  BBC::HDS::MP4::Writer->write( $dst, mdat_at_end( $root ) );
}
else {
  print Data::Dumper->new( [$root] )->Indent( 2 )->Quotekeys( 0 )->Useqq( 1 )->Terse( 1 )
   ->Dump;
}

sub report {
  my $data = shift;
  print hist( "Unhandled boxes", $data->{meta}{unhandled} );
  print hist( "Captured boxes",  $data->{box} );
}

sub hist {
  my ( $title, $hash ) = @_;
  return unless keys %$hash;
  my $ldr  = '# ';
  my $size = sub {
    my $x = shift;
    return scalar @$x if 'ARRAY' eq ref $x;
    return $x;
  };
  my %hist = map { $_ => $size->( $hash->{$_} ) } keys %$hash;
  my @keys = sort { $hist{$b} <=> $hist{$a} } keys %hist;
  my $kw = max 1, map { length $_ } keys %hist;
  my $vw = max 1, map { length $_ } values %hist;
  my $fmt = "$ldr  %-${kw}s : %${vw}d\n";
  print "$ldr$title:\n";
  printf $fmt, $_, $hist{$_} for @keys;
}

sub mdat_at_end {
  my $root = shift;
  my ( @last, @first );
  for my $box ( @$root ) {
    next unless defined $box;
    if ( $box->{type} eq 'mdat' ) {
      push @last, $box;
    }
    else {
      push @first, $box;
    }
  }
  return [ @first, @last ];
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

