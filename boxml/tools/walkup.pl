#!/usr/bin/env perl

package box;

use strict;
use warnings;

package fullbox;

use strict;
use warnings;

our @ISA = qw( box );

sub read {
  my $self = shift;
  return { version => 0, flags => 0xfff };
}

package mybox;

our @ISA = qw( fullbox );

use strict;
use warnings;

sub read {
  my $self = shift;
  return { name => 'My Box' };
}

package main;

use strict;
use warnings;

use Data::Dumper;

my $box = mybox->new;
print Dumper( $box->read_box );

# vim:ts=2:sw=2:sts=2:et:ft=perl

