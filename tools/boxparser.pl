#!/usr/bin/env perl

package reader;

use strict;
use warnings;

sub new {
  my ( $class, $data, $pos, $len ) = @_;
  $pos = 0 unless defined $pos;
  $len = length( $data ) - $pos unless defined $len;
  return bless {
    d => $data,
    p => $pos,
    l => $len,
  }, $class;
}

sub read {
  my ( $self, $count ) = @_;
  return $$self->{len} if $count < 0;

  die "Truncated $self->{d} at offset $self->{p}"
   if $self->{l} < $count;

  my $chunk = substr $self->{d}, $self->{p}, $count;
  $self->{p} += $count;
  $self->{l} -= $count;
  return $chunk;
}

sub avail { shift->{l} }
sub pos   { shift->{p} }

sub read8   { unpack 'C',  shift->read( 1 ) }
sub read16  { unpack 'n',  shift->read( 2 ) }
sub read32  { unpack 'N',  shift->read( 4 ) }
sub read4CC { unpack 'A4', shift->read( 4 ) }

sub read24 {
  my ( $hi, $lo ) = unpack 'Cn', shift->read( 3 );
  return ( $hi << 16 ) | $lo;
}

sub read64 {
  my ( $hi, $lo ) = unpack 'NN', shift->read( 8 );
  return ( $hi << 32 ) | $lo;
}

sub readZ {
  my $self = shift;
  my $tail = substr $self->{d}, $self->{p}, $self->{l};
  my $str  = ( $tail =~ /^(.*?)\0/ ) ? $1 : $tail;
  $self->{p} += length $str + 1;
  return $str;
}

sub readZs {
  my $self = shift;
  [ map { $self->readZ } 1 .. $self->read8 ];
}

package main;

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;

my $src = shift @ARGV;
my $bs  = file( $src )->slurp;

my @boxes = get_boxes( reader->new( $bs ) );
print Dumper( \@boxes );

sub get_box_info {
  my $rdr = shift;

  my $pos  = $rdr->pos;
  my $size = $rdr->read32;
  my $type = $rdr->read4CC;
  $size = $rdr->read64 if $size == 1;

  return {
    size => $size - ( $rdr->pos - $pos ),
    type => $type
  };
}

sub get_full_box {
  my ( $rdr, $bi ) = @_;

  my $ver   = $rdr->read8;
  my $flags = $rdr->read24;

  return {
    %$bi,
    ver   => $ver,
    flags => $flags,
  };
}

sub get_boxes {
  my $rdr   = shift;
  my @boxes = ();
  while ( $rdr->avail ) {
    my $bi = get_box_info( $rdr );
    #    print Dumper( $bi );

    if ( $bi->{type} eq 'abst' ) {
      push @boxes, get_bootstrap_box( $rdr, $bi );
    }
    elsif ( $bi->{type} eq 'afra' ) {
      push @boxes, get_frag_ra_box( $rdr, $bi );
    }
    elsif ( $bi->{type} eq 'mdat' ) {
      push @boxes, get_media_data_box( $rdr, $bi );
    }
    else {
      die "unhandled atom: $bi->{type}\n";
      $rdr->read( $bi->{size} - 8 );
    }
  }
}

sub get_bootstrap_box {
  my ( $rdr, $bi ) = @_;
  my $fbi = get_full_box( $rdr, $bi );

  my %bs = (
    version               => $rdr->read32,
    flags                 => $rdr->read8,
    time_scale            => $rdr->read32,
    current_media_time    => $rdr->read64,
    smpte_timecode_offset => $rdr->read64,
    movie_identifier      => $rdr->readZ,
    servers               => $rdr->readZs,
    quality               => $rdr->readZs,
    drm_data              => $rdr->readZ,
    metadata              => $rdr->readZ,
  );

  $bs{profile} = $bs{flags} >> 6;
  $bs{live}    = ( $bs{flags} & 0x20 ) ? 1 : 0;
  $bs{update}  = ( $bs{flags} & 0x01 ) ? 1 : 0;

  print Dumper( { bi => $fbi, bs => \%bs } );
}

sub get_frag_ra_box {
  my ( $rdr, $bi ) = @_;
}

sub get_media_data_box {
  my ( $rdr, $bi ) = @_;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

