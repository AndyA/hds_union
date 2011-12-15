#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;

sub walk(@);

my $src = shift @ARGV;

my $bs = file( $src )->slurp;

walk $bs, sub {
  my ( $size, $type, $data ) = @_;
  if ( $type eq 'abst' ) {
    my $hdr = substr $data, 0, 35;
    walk substr( $data, 35 ), sub {
      my ( $size, $type, $data ) = @_;
      if ( $type eq 'asrt' ) {
        return $size + 1;
      }
      elsif ( $type eq 'afrt' ) {
        return $size + 1;
      }
      else {
        die "Expected 'asrt', got '$type'\n";
      }
    };
  }
  else {
    die "Expected 'abst', got '$type'\n";
  }
  return $size;
};

sub walk(@) {
  my ( $data, $cb ) = @_;

  my $pos = 0;

  while ( $pos < length $data ) {
    my $size = unpack 'N', substr $data, $pos, 4;
    my $type = substr $data, $pos + 4, 4;
    $pos += 8;
    $size = length $data if $size == 0;
    print "$size, $type\n";
    print hexdump( substr $data, $pos, $size - 8 );
    $pos += $cb->( $size - 8, $type, substr $data, $pos, $size - 8 );
  }

}

# vim:ts=2:sw=2:sts=2:et:ft=perl

