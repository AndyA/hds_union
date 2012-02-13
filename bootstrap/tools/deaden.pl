#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use BBC::HDS::Bootstrap;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;

use Path::Class;

die unless @ARGV == 2;
my ( $src, $dst ) = @ARGV;

my $bs = load_bs( $src );
deaden( $bs );
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

sub deaden {
  my ( $bs ) = @_;
  my $abst = $bs->box( abst => 0 );
  $abst->{data}{live} = 0;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

