#!perl

use strict;
use warnings;

use Test::More;
use Test::Differences;

use Data::Hexdumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;

my @bs = glob 'ref/*.bootstrap';

plan tests => 1 * @bs;

my $HDOPT = {
  output_format     => '  %4a : %16C : %d',
  suppress_warnings => 1
};

for my $src ( @bs ) {
  my $srcd = file( $src )->slurp;

  my $rdr = BBC::HDS::Bootstrap::Reader->new( $srcd );
  my $bs  = $rdr->parse;

  my $wtr  = BBC::HDS::Bootstrap::Writer->new( $bs );
  my $dstd = $wtr->data;

  eq_or_diff hexdump( $dstd, $HDOPT ), hexdump( $srcd, $HDOPT ),
   "$src: roundtrip";
}

# vim:ts=2:sw=2:et:ft=perl

