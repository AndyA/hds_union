#!perl

package TestWriter;

use strict;
use warnings;

use base qw( BBC::HDS::MP4::IOWriter );

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new( undef );
  $self->{__buffer} = '';
  return $self;
}

sub data { shift->{__buffer} }

sub write {
  my ( $self, $data ) = @_;
  $self->{__buffer} .= $data;
  $self;
}

package main;

use strict;
use warnings;

use Test::More tests => 7;

sub writer() { TestWriter->new }

is( writer->write8( 65, 66 )->data, 'AB', 'write8' );
is( writer->write16( 0x4142 )->data,     'AB',   'write16' );
is( writer->write24( 0x414243 )->data,   'ABC',  'write24' );
is( writer->write32( 0x41424344 )->data, 'ABCD', 'write32' );
is( writer->write64( ( 0x41424344 << 32 ) | 0x45464748 )->data, 'ABCDEFGH', 'write64' );
is( writer->write4CC( 'ab' )->data, 'ab  ', 'write4CC4CC4CC4CC' );

is( writer->writeZs( 'a', 'bb', 'ccc' )->data, "\x03a\0bb\0ccc\0", 'writeZs' );

# vim:ts=2:sw=2:et:ft=perl

