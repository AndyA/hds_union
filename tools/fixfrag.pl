#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use List::Util qw( min );

use constant CHUNK => 65536;

my ( $src, $dst ) = @ARGV;
die unless defined $dst;
my $in  = file( $src )->openr;
my $out = file( $dst )->openw;

my $fsize = ( stat $src )[7];

my %COPY = map { $_ => 1 } qw( ftyp moov moof mdat );

atom_walk( $in, $out );

sub atom_walk {
  my ( $in, $out ) = @_;

  my $pos = tell $in;
  my $rb  = read_bytes( $in );
  while ( 1 ) {
    my $atom = $pos;
    seek $in, $atom, 0;

    my ( $size, $fourcc, $hdr_len ) = parse_header( $rb );
    last unless defined $size;
    $size = $fsize - $pos if $size == 0;
    my $body_len = $size - $hdr_len;

    $pos += $size;

    if ( $COPY{$fourcc} ) {
      printf "%08x %10d '%s' --> destination\n", $pos, $size, $fourcc;
      #      my $hdr = make_header( $size, $fourcc );
      #      my $put = syswrite $out, $hdr;
      #      die "IO Error: $!" unless defined $put;
      #      die "Short write" if $put < length $hdr;
      seek $in, $atom, 0;
      copy( $in, $out, $size );
    }
    else {
      printf "%08x %10d '%s'\n", $pos, $size, $fourcc;
    }

  }
}

sub make_header {
  my ( $size, $fourcc ) = @_;
  return make_header( 1, $fourcc ) . pack 'NN', $size > 32, $size
   if $size > 0xffffffff;
  return pack 'NA4', $size, $fourcc;
}

sub copy {
  my ( $src, $dst, $len ) = @_;

  my $data;
  while ( $len > 0 ) {
    my $toread = min( $len, CHUNK );
    $data = '';
    my $got = sysread $src, $data, $toread;
    last if $got == 0;
    die "IO Error: $!\n" unless defined $got;
    my $put = syswrite $dst, $data;
    $len -= $got;
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
  my $fh = shift;
  return sub {
    my $len = shift;
    my $got = sysread( $fh, my $data, $len );
    die "IO error: $!\n" unless defined $got;
    return $data if $got == $len;
    warn "Short read: $got < $len\n" if $got > 0;
    return;
  };
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

