#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use List::Util qw( min );

use constant DUMP => 256;

my $src   = shift;
my $fh    = file( $src )->openr;
my $fsize = ( stat $src )[7];

my %STOP = map { $_ => 1 } qw( traf );

atom_walk( $fh );

sub atom_walk {
  my $fh    = shift;
  my $limit = shift;
  my $depth = shift || 0;

  my $pad = '  ' x $depth;
  my $pos = tell $fh;
  my $rb  = read_bytes( $fh, $limit );
  while ( 1 ) {
    my $atom = $pos;
    seek $fh, $atom, 0;

    my ( $size, $fourcc, $hdr_len ) = parse_header( $rb );
    last unless defined $size;
    $size = $fsize - $pos if $size == 0;

    printf "%s%08x %10d '%s'\n", $pad, $pos, $size, $fourcc;
    $pos += $size;

    if ( !$STOP{$fourcc} ) {
      my $avail = $size - $hdr_len;
      my $peek = $rb->( min( $avail, DUMP ) );
      if ( defined $peek ) {
        my ( $nsz, $nfcc, $nhl ) = parse_header( read_string( $peek ) );
        if ( defined $nsz ) {
          $nsz = $size - $nhl if $nsz == 0;
          if ( $nsz >= 8 && $nsz < $fsize && $nfcc =~ /^[a-z]{4}$/ ) {
            seek $fh, $hdr_len + $atom, 0;
            atom_walk( $fh, $avail, $depth + 1 );
          }
        }
      }
    }
  }
}

sub parse_header {
  my $rb = shift;

  my $hdr_len = 8;
  my $bytes   = $rb->( 8 );
  return unless defined $bytes;

  my ( $size, $fourcc ) = unpack 'NA4', $bytes;

  if ( $size == 1 ) {
    my $ex = $rb->( 8 );
    return unless defined $ex;
    my ( $hi, $lo ) = unpack 'NN', $ex;
    $size = ( $hi << 32 ) | $lo;
    $hdr_len += 8;
  }

  return ( $size, $fourcc, $hdr_len );

}

sub read_string {
  my $str = shift;
  return sub {
    my $len   = shift;
    my $avail = length $str;
    return if $avail == 0;
    if ( $avail < $len ) {
      warn "Short read: $avail < $len\n";
      return;
    }
    my $data = substr $str, 0, $len;
    $str = substr $str, $len;
    return $data;
  };
}

sub read_bytes {
  my ( $fh, $limit ) = @_;
  $limit += tell $fh if defined $limit;
  return sub {
    my $len = shift;
    my $to_read
     = defined $limit ? min( $len, $limit - tell $fh ) : $len;
    return if $to_read == 0;
    my $got = sysread( $fh, my $data, $to_read );
    die "IO error: $!\n" unless defined $got;
    return $data if $got == $len;
    warn "Short read: $got < $len\n" if $got > 0;
    return;
   }
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

