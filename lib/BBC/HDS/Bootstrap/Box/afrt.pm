package BBC::HDS::Bootstrap::Box::afrt;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Box );

=head1 NAME

BBC::HDS::Bootstrap::Box::afrt - afrt box

=cut

sub frag_id_by_time {
  my ( $self, $time, $duration, $live ) = @_;
}

sub _find_fdp {
  my ( $self, $time ) = @_;
  return if $time < 0;
  my $runs = $self->runs;
  return unless @$runs;
  for my $i ( 1 .. $#$runs ) {
    return $runs->[ $i - 1 ]
     if $runs->[$i]{accrued} >= $time;
  }
  return $runs->[-1];
}

sub _end_of_play {
  my ( $self, $pair ) = @_;
  return $pair->{duration} == 0 && !$pair->{discontinuity};
}

sub _fai {
  my ( $self, $pair, $fid ) = @_;
  return {
    fid      => $fid,
    duration => $pair->{duration},
    end_time => $pair->{accrued}
     + $pair->{duration} * ( $fid - $pair->{first} + 1 ),
  };
}

sub _next_valid {
  my ( $self, $i, $fid, $duration ) = @_;
  my $runs = $self->runs;
  for my $ii ( $i .. $#$runs ) {
    my $p = $runs->[$ii];
    return $self->_fai( $p, $fid ) if $p->{duration};
    $fid = 0;
  }
  return;
}

sub _find_valid {
  my ( $self, $fid, $duration ) = @_;
  my $runs = $self->runs;
  for my $i ( 0 .. $#$runs - 1 ) {
    my ( $p, $np ) = @{$runs}[ $i, $i + 1 ];
    next if $p->{first} > $fid;
    return $self->_next_valid( $i, $duration ) if $np->{first} > $fid;
    if ( $self->_end_of_play( $np ) && $p->{duration} ) {
      my $residue  = $duration - $np->{accrued};
      my $start    = ( $fid - $p->{first} ) * $p->{duration};
      my $distance = $start + $p->{duration};
      next if $residue <= $start;
    }
  }
}

sub _validate_frag {
  my ( $self, $fid, $duration, $live ) = @_;
  my $runs = $self->runs;
  my $fai  = undef;
}

sub _frag_id {
  my ( $self, $pair, $time ) = @_;
  return $pair->{first} if $pair->{duration} == 0;
  return $pair->{first}
   + int( ( $time - $pair->{accrued} ) / $pair->{duration} );
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
