#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use BBC::HDS::Bootstrap;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;

use Getopt::Long;
use Path::Class;

GetOptions( 'duration:i' => \my $Duration ) or die;
die unless @ARGV == 2;
my ( $src, $dst ) = @ARGV;

my $bs = load_bs( $src );
enliven( $bs, $Duration );
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

sub enliven {
  my ( $bs, $dur ) = @_;
  my $abst = $bs->box( abst => 0 );
  my $rt   = $abst->run_table;
  my @nrt  = map { limit_run( $_, $dur ) } @$rt;
  $abst->set_run_table( \@nrt );
  $abst->{data}{live} = 1;
  my $last = $nrt[0][-1]{f}[-1];
  $abst->{data}{current_media_time}
   = defined $last ? $last->{timestamp} + $last->{duration} : 0;
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

