
use File::Basename;
use File::Path;
use File::Spec;
use HTTP::Proxy::BodyFilter::save;
use HTTP::Proxy;
use POSIX qw( strftime );
use Time::HiRes qw( time );
use URI;

use constant OUT => 'ref/proxycap';

my $proxy = HTTP::Proxy->new( port => 8888, logmask => 0x22 );

$proxy->push_filter(
  host     => qr{.bbc\.co\.uk}i,
  mime     => '*/*',
  response => HTTP::Proxy::BodyFilter::save->new(
    filename => sub {
      my $msg = shift;
      my $uri = URI->new( $msg->request->uri )->canonical;
      my $now = time;
      my ( $sec, $msec ) = ( int( $now ), $now * 1_000 % 1_000 );
      my @path = split /\//, $uri->path;
      my $name = join(
        '-',
        sprintf( '%s.%03d',
          strftime( '%Y%m%d-%H%M%S', gmtime $sec ), $msec ),
        $uri->host,
        @path
      );
      return File::Spec->rel2abs( File::Spec->catfile( OUT, $name ) );
    }
  )
);

$proxy->start;
