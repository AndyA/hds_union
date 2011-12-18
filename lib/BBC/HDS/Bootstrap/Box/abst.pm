package BBC::HDS::Bootstrap::Box::abst;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Box );

=head1 NAME

BBC::HDS::Bootstrap::Box::abst - abst box

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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
