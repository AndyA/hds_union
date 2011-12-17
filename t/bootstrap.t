#!perl

use strict;
use warnings;

use BBC::HDS::Bootstrap::Reader;
use Data::Dumper;
use File::Spec;
use Path::Class;

use Test::More tests => 6;

my $src  = File::Spec->catfile( 'ref', 'inlet1.bootstrap' );
my $data = file( $src )->slurp;
my $bs   = BBC::HDS::Bootstrap::Reader->new( $data )->parse;

isa_ok $bs, 'BBC::HDS::Bootstrap';
my $abst = $bs->box( abst => 0 );
isa_ok $abst, 'BBC::HDS::Bootstrap::Box';
isa_ok $abst, 'BBC::HDS::Bootstrap::Box::abst';
my $afrt = $abst->box( afrt => 0 );
isa_ok $afrt, 'BBC::HDS::Bootstrap::Box';
isa_ok $afrt, 'BBC::HDS::Bootstrap::Box::afrt';

is $abst->current_media_time, 752262158, 'read property';

# vim:ts=2:sw=2:et:ft=perl

