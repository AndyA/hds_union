package BBC::HDS::Bootstrap::Reader;

use strict;
use warnings;

use BBC::HDS::Bootstrap::ByteReader;

=head1 NAME

BBC::HDS::Bootstrap::Reader - Read a bootstrap

=cut

sub new {
  my ( $class, $data ) = @_;
  bless { data => $data }, $class;
}

sub parse {
  my $self = shift;
  return _get_boxes(
    BBC::HDS::Bootstrap::ByteReader->new( $self->{data} ) );
}

sub _get_box_info {
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

sub _get_full_box {
  my ( $rdr, $bi ) = @_;

  my $ver   = $rdr->read8;
  my $flags = $rdr->read24;

  return {
    %$bi,
    ver   => $ver,
    flags => $flags,
  };
}

sub _get_boxes {
  my $rdr   = shift;
  my @boxes = ();
  while ( $rdr->avail ) {
    my $bi = _get_box_info( $rdr );

    if ( $bi->{type} eq 'abst' ) {
      push @boxes, _get_bootstrap_box( $rdr, $bi );
    }
    elsif ( $bi->{type} eq 'afra' ) {
      push @boxes, _get_frag_ra_box( $rdr, $bi );
    }
    elsif ( $bi->{type} eq 'mdat' ) {
      push @boxes, _get_media_data_box( $rdr, $bi );
    }
    else {
      die "unhandled atom: $bi->{type}\n";
      $rdr->read( $bi->{size} - 8 );
    }
  }
  return \@boxes;
}

sub _expect_box {
  my ( $rdr, $type ) = @_;
  my $bi = _get_box_info( $rdr );
  die "Expected '$type', got '$bi->{type}'" unless $bi->{type} eq $type;
  return _get_full_box( $rdr, $bi );
}

sub _get_segment_runs {
  my $rdr = shift;
  _expect_box( $rdr, 'asrt' );
  return {
    quality => $rdr->readZs,
    runs    => $rdr->read32ar(
      sub {
        my $rdr = shift;
        {
          first => $rdr->read32,
          frags => $rdr->read32
        };
      }
    ),
  };
}

sub _get_frag_duration_pair {
  my $rdr = shift;
  my $rec = {
    first     => $rdr->read32,
    timestamp => $rdr->read64,
    duration  => $rdr->read32,
  };
  $rec->{discontinuity} = $rdr->read8 if $rec->{duration} == 0;
  return $rec;
}

sub _get_fragment_runs {
  my $rdr = shift;
  _expect_box( $rdr, 'afrt' );
  return {
    timescale => $rdr->read32,
    quality   => $rdr->readZs,
    runs      => $rdr->read32ar( \&_get_frag_duration_pair ),
  };
}

sub _get_bootstrap_box {
  my ( $rdr, $bi ) = @_;

  my %bs = (
    bi                    => _get_full_box( $rdr, $bi ),
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
    segment_run_tables    => $rdr->read8ar( \&_get_segment_runs ),
    fragment_run_tables => $rdr->read8ar( \&_get_fragment_runs ),
  );

  $bs{profile} = $bs{flags} >> 6;
  $bs{live}    = ( $bs{flags} & 0x20 ) ? 1 : 0;
  $bs{update}  = ( $bs{flags} & 0x01 ) ? 1 : 0;

  return \%bs;
}

sub _get_frag_ra_box {
  my ( $rdr, $bi ) = @_;
  my $fbi = _get_full_box( $rdr, $bi );

  my $sizes = $rdr->read8;

  my $rd_id
   = ( $sizes & 0x80 ) ? sub { $rdr->read32 } : sub { $rdr->read16 };
  my $rd_ofs
   = ( $sizes & 0x40 ) ? sub { $rdr->read64 } : sub { $rdr->read32 };

  my %ra = (
    bi         => $fbi,
    sizes      => $sizes,
    time_scale => $rdr->read32,
    local      => $rdr->read32ar(
      sub {
        my $rdr = shift;
        return {
          time   => $rdr->read64,
          offset => $rd_ofs->()
        };
      }
    ),
  );

  if ( $sizes & 0x20 ) {
    $ra{gloabls} = $rdr->read32ar(
      sub {
        my $rdr = shift;
        return {
          time             => $rdr->read64(),
          segment          => $rd_id->(),
          fragment         => $rd_id->(),
          afra_offset      => $rd_ofs->(),
          offset_from_afra => $rd_ofs->(),
        };
      }
    );
  }

  return \%ra;
}

sub _get_media_data_box {
  my ( $rdr, $bi ) = @_;
  return {
    bi   => $bi,
    data => $rdr->read( $bi->{size} )
  };
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
