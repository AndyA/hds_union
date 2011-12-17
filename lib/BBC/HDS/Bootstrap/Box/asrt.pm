package BBC::HDS::Bootstrap::Box::asrt;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Box );

=head1 NAME

BBC::HDS::Bootstrap::Box::asrt - asrt box

=cut

sub segment_by_frag_id {
  my ( $self, $fid ) = @_;
  my $sfp = $self->_find_sfp( $fid );
  return unless $sfp;
  return $self->_calc_seg_id( $sfp, $fid );
}

sub _find_sfp {
  my ( $self, $fid ) = @_;
  return if $fid < 1;
  my $runs = $self->runs;
  return unless @$runs;
  for my $i ( 1 .. $#$runs ) {
    return $runs->[ $i - 1 ]
     if $runs->[$i]{accrued} >= $fid;
  }
  return $runs->[-1];
}

sub _calc_seg_id {
  my ( $self, $sfp, $fid ) = @_;
  return $sfp->{first}
   + int( ( $fid - $sfp->{accrued} - 1 ) / $sfp->{frags} );
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
