#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/../lib";

use constant FPS => 25;

use BBC::HDS::Bootstrap;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;

use Data::Dumper;
use Getopt::Long;
use Path::Class;

GetOptions( 'duration:i' => \my $Duration ) or die;
die unless @ARGV == 2;
my ( $src, $dst ) = @ARGV;

my $bs = load_bs( $src );
gapper( $bs, $Duration );
save_bs( $dst, $bs );

sub save_bs {
  my ( $dst, $bs ) = @_;
  my $data = BBC::HDS::Bootstrap::Writer->new( $bs )->data;
  print { file( $dst )->openw } $data;
}

sub load_bs {
  my $src  = shift;
  my $data = file( $src )->slurp;
  return BBC::HDS::Bootstrap::Reader->new( $data )->parse;
}

sub fmt_time {
  my $ts  = shift;
  my @div = ( FPS, 60, 60, 24 );
  my @p   = ();
  $ts = int( $ts * FPS );
  while ( my $div = shift @div ) {
    unshift @p, sprintf '%02d', $ts % $div;
    $ts = int( $ts / $div );
  }
  return join ':', @p;
}

sub gapper {
  my ( $bs ) = @_;
  my $abst = $bs->box( abst => 0 );
  my $rt   = $abst->run_table;
  my $seg  = splice @{ $rt->[0] }, 2, 1;
  print "Deleted segment at ", fmt_time( $seg->{f}[0]->{timestamp} / 1000 ), "\n";
  #  print Dumper($frag);
  #  print Dumper( $rt );
  $abst->set_run_table( $rt );
  #  my @nrt  = map { limit_run( $_, $dur ) } @$rt;
  #  $abst->set_run_table( \@nrt );
  #  $abst->{data}{live} = 1;
  #  my $last = $nrt[0][-1]{f}[-1];
  #  $abst->{data}{current_media_time}
  #   = defined $last ? $last->{timestamp} + $last->{duration} : 0;
}

sub limit_run {
  my ( $rt, $dur ) = @_;
  my $cum = 0;
  my @ns  = ();
  SEG: for my $seg ( @$rt ) {
    my @nf = ();
    FRAG: for my $fr ( @{ $seg->{f} } ) {
      last SEG if $fr->{duration} == 0 && $fr->{discontinuity} == 0;
      last FRAG if defined $dur && $cum >= $dur;
      push @nf, $fr;
      $cum += $fr->{duration};
    }
    last SEG unless @nf;
    push @ns, { first => $seg->{first}, frags => scalar( @nf ), f => \@nf };
  }
  return \@ns;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

