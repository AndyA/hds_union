package BBC::HDS::Bootstrap::Box::abst;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Box );

=head1 NAME

BBC::HDS::Bootstrap::Box::abst - abst box

=cut

=for NOTES

TODO figure out the semantics of missing fragments. Does a missing
fragment make a gap in a segment?

=cut

sub _build_index {
  my $self = shift;
  my $box  = $self->data;
  my @box  = (
    @{ $box->{segment_run_tables}  || [] },
    @{ $box->{fragment_run_tables} || [] }
  );
  my %idx = ();
  for my $box ( @box ) {
    my $type = $box->{bi}{type};
    push @{ $idx{$type} }, $box;
  }
  return \%idx;
}

sub index {
  my $self = shift;
  $self->{index} ||= $self->_build_index;
}

sub _frag_factory {
  my ( $self, $frt ) = @_;

  my $prev = undef;
  my $done = 0;
  my $ts   = $frt->{timescale};
  my @frt  = @{ $frt->{runs} || [] };
  die "Empty fragment run table\n" unless @frt;
  my $idx = $frt[0]{first};

  my $inspect = sub {
    my $frag = shift;
    $done++ if $frag->{duration} == 0 && !$frag->{discontinuity};
    return $frag;
  };

  my $make_frag = sub {
    my $type = shift;
    die "Ran out of fragments\n" unless $prev;
    my $frag = {
      first     => $idx,
      duration  => $prev->{duration},
      type      => $type,
      timestamp => $prev->{timestamp} + $prev->{duration},
    };
    $idx++;
    return $inspect->( $prev = $frag );
  };

  return sub {
    return ( scalar( @frt ), $done ) if @_;
    FRAG: while ( @frt ) {
      my $first = $frt[0]{first};

      if ( $first > 0 && $first < $idx ) {
        warn "Dropping out-out-of-order fragment ($first < $idx)\n";
        $inspect->( shift @frt );
        redo FRAG;
      }

      if ( $first == 0 || $first == $idx ) {
        $idx++ if $first > 0;
        return $prev
         = { %{ $inspect->( shift @frt ) }, type => 'real', };
      }

      return $make_frag->( 'interpolated' );
    }

    return $make_frag->( 'extrapolated' );
  };
}

sub _make_run_table {
  my $self = shift;

  my $box = $self->data;

  my @srt = @{ $box->{segment_run_tables}  || [] };
  my @frt = @{ $box->{fragment_run_tables} || [] };

  my @rts = ();

  while ( my $srt = shift @srt ) {
    my $frt = shift @frt;
    last unless $frt;

    my $next_frag = $self->_frag_factory( $frt );

    my $rt = [];
    my @runs = @{ $srt->{runs} || [] };
    while ( my $seq = shift @runs ) {
      # What do discontinuities in the segment numbering mean?
      my $rec = { %$seq, f => [] };
      for ( 1 ... $seq->{frags} ) {
        push @{ $rec->{f} }, $next_frag->();
      }
      push @$rt, $rec;
    }

    # Extra fragments?
    my @xf = ();
    while ( 1 ) {
      my $frag = $next_frag->();
      last unless $frag && $frag->{type} ne 'extrapolated';
      push @xf, $frag;
    }
    push @$rt, { f => \@xf } if @xf;
    push @rts, $rt;
  }

  return \@rts;
}

sub run_table {
  my $self = shift;
  $self->{runtable} ||= $self->_make_run_table;
}

sub _make_next {
  my ( $self, $prev ) = @_;
  return unless $prev;
  return {
    first     => $prev->{first} + 1,
    duration  => $prev->{duration},
    timestamp => $prev->{timestamp} + $prev->{duration},
  };
}

sub set_run_table {
  my ( $self, $rts ) = @_;

  my $box = $self->data;

  my @srt = ();
  my @frt = ();

  for my $rt ( @$rts ) {
    my $segs  = [];
    my $frags = [];
    my $prev  = undef;
    for my $seg ( @$rt ) {
      push @$segs, { first => $seg->{first}, frags => $seg->{frags} }
       if exists $seg->{first};
      F: for my $frag ( @{ $seg->{f} } ) {
        my $next = $self->_make_next( $prev );
        if ( !exists $frag->{discontinuity}
          && $frag->{duration} != 0
          && $next
          && !exists $next->{discontinuity}
          && $next->{first} == $frag->{first}
          && $next->{timestamp} == $frag->{timestamp}
          && $next->{duration} == $frag->{duration} ) {
          $prev = $next;
          next F;
        }
        $prev = {%$frag};
        delete $prev->{type};
        push @$frags, $prev;
      }
    }
    push @srt, $segs;
    push @frt, $frags;
  }

  $box->{segment_run_tables}  = \@srt;
  $box->{fragment_run_tables} = \@frt;
  delete $self->{runtable};
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
