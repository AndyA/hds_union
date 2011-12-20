
use Getopt::Long;
use File::Basename;
use File::Path qw( make_path );
use File::Spec;
use File::Which;
use HTTP::Proxy::BodyFilter::save;
use HTTP::Proxy;
use POSIX qw( strftime );
use Time::HiRes qw( time );
use URI;

sub timestamp() {
  my $tm = time;
  my ( $sec, $msec ) = ( int( $tm ), $tm * 1_000 % 1_000 );
  sprintf( '%s.%03d', strftime( '%Y%m%d-%H%M%S', gmtime $sec ), $msec );
}

use constant PORT    => 8888;
use constant LOGMASK => 0x00;    # 0x22
use constant OUT => File::Spec->catfile( 'proxycap', timestamp );

my @host = ();
my $mime = '*/*';
GetOptions( 'host:s' => \@host, 'mime:s' => \$mime ) or die;
my $host_re = qr{@{[join '|', 
 map { quotemeta } map { split /\s*,\s*/ } @host]}}i;

$SIG{INT} = sub { disable_proxy() };

make_path( OUT );
my $proxy = HTTP::Proxy->new( port => PORT, logmask => LOGMASK );

$proxy->push_filter(
  host     => $host_re,
  mime     => $mime,
  response => HTTP::Proxy::BodyFilter::save->new(
    filename => sub {
      my $msg  = shift;
      my $uri  = URI->new( $msg->request->uri )->canonical;
      my $name = File::Spec->rel2abs(
        File::Spec->catfile(
          OUT,
          join( '-', timestamp, $uri->host, split /\//, $uri->path )
        )
      );
      print "Saving $name\n";
      return $name;
    }
  )
);

enable_proxy();
$proxy->start;
disable_proxy();

sub enable_proxy {
  print "Enabling proxy\n";
  system perl => 'tools/setproxy.pl', "http://localhost:@{[ PORT ]}";
}

sub disable_proxy {
  print "Disabling proxy\n";
  system perl => 'tools/setproxy.pl', '--disable';
}
