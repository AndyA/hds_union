#!/usr/bin/env perl

use strict;
use warnings;

use Data::Hexdumper;
use List::Util qw( min max );
use Test::More tests => 15;

{
  my $test = pack 'N', 0b1_00_101_1011_11000_010100_1011100_0011;
  #print hexdump( $test );
  my $br = bit_reader( $test );
  is $br->( 1 ), 0b1,       '1 bit';
  is $br->( 2 ), 0b00,      '2 bits';
  is $br->( 3 ), 0b101,     '3 bits';
  is $br->( 4 ), 0b1011,    '4 bits';
  is $br->( 5 ), 0b11000,   '5 bits';
  is $br->( 6 ), 0b010100,  '6 bits';
  is $br->( 7 ), 0b1011100, '7 bits';
  is $br->( 4 ), 0b0011,    '4 bits';
  eval { $br->( 1 ) };
  ok $@, 'error';
}

{
  is exp_gol( 0b1000_0000_0000_0000_0000_0000_0000_0000 ), 0, 'eg 0';
  is exp_gol( 0b0100_0000_0000_0000_0000_0000_0000_0000 ), 1, 'eg 1';
  is exp_gol( 0b0110_0000_0000_0000_0000_0000_0000_0000 ), 2, 'eg 2';
  is exp_gol( 0b0010_0000_0000_0000_0000_0000_0000_0000 ), 3, 'eg 3';
  is exp_gol( 0b0010_1000_0000_0000_0000_0000_0000_0000 ), 4, 'eg 4';
  is exp_gol( 0b0011_0000_0000_0000_0000_0000_0000_0000 ), 5, 'eg 5';
}

sub exp_gol { read_exp_gol( bit_reader( pack 'N*', @_ ) ) }

sub read_exp_gol {
  my $br = shift;
  my $lz = 0;
  $DB::single = 1;
  $lz++ while $br->( 1 ) == 0;
  return ( 1 << $lz ) - 1 + $br->( $lz );
}

sub bit_reader {
  my @data = map ord, split //, shift;
  my $pos = 0;

  return sub {
    my $len = shift;
    my $v   = 0;
    while ( $len > 0 ) {
      die unless @data;

      my $mask  = 0xff >> $pos;
      my $avail = 8 - $pos;
      my $shift = max( 0, $avail - $len );
      my $got   = min( $avail, $len );

      $v <<= $got;
      $v |= ( $data[0] & $mask ) >> $shift;

      $len -= $got;
      $pos += $got;

      if ( $pos >= 8 ) {
        $pos -= 8;
        shift @data;
      }
    }
    return $v;
  };
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

