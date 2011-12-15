package BBC::HDS::Bootstrap::Writer;

use strict;
use warnings;

use Carp qw( croak );

use BBC::HDS::Bootstrap::BoxWriter;

=head1 NAME

BBC::HDS::Bootstrap::Writer - Write bootstraps

=cut

sub new {
  my ( $class, $bs ) = @_;
  bless { bs => $bs }, $class;
}

sub data {
  my $self = shift;
  my @box  = ();
  for my $atom ( @{ $self->{bs} } ) {
    my $type = $atom->{bi}{type};
    my $wtr  = $self->_writer( $atom->{bi} );
    if ( $type eq 'abst' ) {
      $self->_put_bootstrap_box( $wtr, $atom );
    }
    elsif ( $type eq 'afra' ) {
      $self->_put_frag_ra_box( $wtr, $atom );
    }
    elsif ( $type eq 'mdat' ) {
      $self->_put_media_data_box( $wtr, $atom );
    }
    else {
      croak "Unsupported atom type '$type'";
    }
    push @box, $wtr;
  }
  return join '', map { $_->box } @box;
}

sub _put_full_box {
  my ( $self, $wtr, $bi ) = @_;
  $wtr->write8( $bi->{ver} );
  $wtr->write24( $bi->{flags} );
}

sub _writer {
  my ( $self, $bi ) = @_;
  my $wtr = BBC::HDS::Bootstrap::BoxWriter->new( $bi->{type} );
  $self->_put_full_box( $wtr, $bi );
  return $wtr;
}

sub _put_bootstrap_box {
  my ( $self, $wtr, $atom ) = @_;

  my $flags
   = ( $atom->{profile} << 6 ) | ( $atom->{live} ? 0x20 : 0x00 )
   | ( $atom->{update} ? 0x01 : 0x00 );

  $wtr->write32( $atom->{version} )->write8( $flags )
   ->write32( $atom->{time_scale} )
   ->write64( $atom->{current_media_time} )
   ->write64( $atom->{smpte_timecode_offset} )
   ->writeZ( $atom->{movie_identifier} )
   ->writeZs( @{ $atom->{servers} } )->writeZs( @{ $atom->{quality} } )
   ->writeZ( $atom->{drm_data} )->writeZ( $atom->{metadata} );

  $self->_put_segment_runs( $wtr, $atom->{segment_run_tables} );
  $self->_put_fragment_runs( $wtr, $atom->{fragment_run_tables} );
}

sub _put_segment_runs {
  my ( $self, $wtr, $runs ) = @_;

  $wtr->write8ar(
    sub {
      my ( undef, $run ) = @_;

      my $w = $self->_writer( $run->{bi} );

      $w->writeZs( @{ $run->{quality} } );
      $w->write32ar(
        sub {
          my ( undef, $seg ) = @_;
          $w->write32( $seg->{first}, $seg->{frags} );
        },
        @{ $run->{runs} }
      );

      $wtr->write( $w->box );

    },
    @$runs
  );
}

sub _put_fragment_runs {
  my ( $self, $wtr, $runs ) = @_;

  $wtr->write8ar(
    sub {
      my ( undef, $run ) = @_;

      my $w = $self->_writer( $run->{bi} );

      $w->write32( $run->{timescale} );
      $w->writeZs( @{ $run->{quality} } );
      $w->write32ar(
        sub {
          my ( undef, $seg ) = @_;
          $w->write32( $seg->{first} );
          $w->write64( $seg->{timestamp} );
          $w->write32( $seg->{duration} );
          $w->write8( $seg->{discontinuity} || 0 )
           if $seg->{duration} == 0;
        },
        @{ $run->{runs} }
      );

      $wtr->write( $w->box );

    },
    @$runs
  );
}

sub _put_frag_ra_box {
  my ( $self, $wtr, $atom ) = @_;
}

sub _put_media_data_box {
  my ( $self, $wtr, $atom ) = @_;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
