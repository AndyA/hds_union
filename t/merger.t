#!perl

use strict;
use warnings;

use BBC::HDS::Bootstrap::Merger;
use Data::Dumper;
use Test::Differences;
use Test::More;

my @tests = (
  {
    name  => 'nop',
    merge => [
      [
        {
          bi => { flags => 0, ver => 0, type => 'abst' },
          current_media_time    => 752262158,
          drm_data              => '',
          flags                 => 32,
          live                  => 1,
          metadata              => '',
          movie_identifier      => '',
          profile               => 0,
          quality               => [],
          servers               => [],
          smpte_timecode_offset => 0,
          time_scale            => 1000,
          update                => 0,
          version               => 1,
          segment_run_tables    => [
            {
              runs    => [ { first => 18626, frags => 10 }, ],
              quality => [],
              bi => { flags => 0, ver => 0, type => 'asrt' }
            }
          ],
          fragment_run_tables => [
            {
              timescale => 1000,
              runs      => [
                {
                  first     => 186251,
                  timestamp => 745002164,
                  duration  => 4000
                }
              ],
              quality => [],
              bi      => { flags => 0, ver => 0, type => 'afrt' }
            }
          ]
        }
      ],
      [
        {
          bi => { flags => 0, ver => 0, type => 'abst' },
          current_media_time    => 752262158,
          drm_data              => '',
          flags                 => 32,
          live                  => 1,
          metadata              => '',
          movie_identifier      => '',
          profile               => 0,
          quality               => [],
          servers               => [],
          smpte_timecode_offset => 0,
          time_scale            => 1000,
          update                => 0,
          version               => 1,
          segment_run_tables    => [
            {
              runs    => [ { first => 18626, frags => 10 }, ],
              quality => [],
              bi => { flags => 0, ver => 0, type => 'asrt' }
            }
          ],
          fragment_run_tables => [
            {
              timescale => 1000,
              runs      => [
                {
                  first     => 186251,
                  timestamp => 745002164,
                  duration  => 4000
                }
              ],
              quality => [],
              bi      => { flags => 0, ver => 0, type => 'afrt' }
            }
          ]
        }
      ],
    ],
    expect => [
      {
        bi => { flags => 0, ver => 0, type => 'abst' },
        current_media_time    => 752262158,
        drm_data              => '',
        flags                 => 32,
        live                  => 1,
        metadata              => '',
        movie_identifier      => '',
        profile               => 0,
        quality               => [],
        servers               => [],
        smpte_timecode_offset => 0,
        time_scale            => 1000,
        update                => 0,
        version               => 1,
        segment_run_tables    => [
          {
            runs    => [ { first => 18626, frags => 10 }, ],
            quality => [],
            bi => { flags => 0, ver => 0, type => 'asrt' }
          }
        ],
        fragment_run_tables => [
          {
            timescale => 1000,
            runs      => [
              {
                first     => 186251,
                timestamp => 745002164,
                duration  => 4000
              }
            ],
            quality => [],
            bi      => { flags => 0, ver => 0, type => 'afrt' }
          }
        ]
      }
    ],
  },
  {
    name  => 'simple',
    merge => [
      [
        {
          bi => { flags => 0, ver => 0, type => 'abst' },
          current_media_time    => 752262158,
          drm_data              => '',
          flags                 => 32,
          live                  => 1,
          metadata              => '',
          movie_identifier      => '',
          profile               => 0,
          quality               => [],
          servers               => [],
          smpte_timecode_offset => 0,
          time_scale            => 1000,
          update                => 0,
          version               => 1,
          segment_run_tables    => [
            {
              runs    => [ { first => 18626, frags => 10 }, ],
              quality => [],
              bi => { flags => 0, ver => 0, type => 'asrt' }
            }
          ],
          fragment_run_tables => [
            {
              timescale => 1000,
              runs      => [
                {
                  first     => 186251,
                  timestamp => 745002164,
                  duration  => 4000
                }
              ],
              quality => [],
              bi      => { flags => 0, ver => 0, type => 'afrt' }
            }
          ]
        }
      ],
      [
        {
          bi => { flags => 0, ver => 0, type => 'abst' },
          current_media_time    => 753497919,
          drm_data              => '',
          flags                 => 32,
          live                  => 1,
          metadata              => '',
          movie_identifier      => '',
          profile               => 0,
          quality               => [],
          servers               => [],
          smpte_timecode_offset => 0,
          time_scale            => 1000,
          update                => 0,
          version               => 1,
          segment_run_tables    => [
            {
              runs    => [ { first => 18627, frags => 10 }, ],
              quality => [],
              bi => { flags => 0, ver => 0, type => 'asrt' }
            }
          ],
          fragment_run_tables => [
            {
              timescale => 1000,
              runs      => [
                {
                  first     => 186252,
                  timestamp => 745006164,
                  duration  => 4000
                }
              ],
              quality => [],
              bi      => { flags => 0, ver => 0, type => 'afrt' }
            }
          ]
        }
      ],
    ],
    expect => [
      {
        bi => { flags => 0, ver => 0, type => 'abst' },
        current_media_time    => 753497919,
        drm_data              => '',
        flags                 => 32,
        live                  => 1,
        metadata              => '',
        movie_identifier      => '',
        profile               => 0,
        quality               => [],
        servers               => [],
        smpte_timecode_offset => 0,
        time_scale            => 1000,
        update                => 0,
        version               => 1,
        segment_run_tables    => [
          {
            runs => [
              { first => 18626, frags => 10 },
              { first => 18627, frags => 10 },
            ],
            quality => [],
            bi      => { flags => 0, ver => 0, type => 'asrt' }
          }
        ],
        fragment_run_tables => [
          {
            timescale => 1000,
            runs      => [
              {
                first     => 186251,
                timestamp => 745002164,
                duration  => 4000
              },
              {
                first     => 186252,
                timestamp => 745006164,
                duration  => 4000
              }
            ],
            quality => [],
            bi      => { flags => 0, ver => 0, type => 'afrt' }
          }
        ]
      }
    ],
  },
);

plan tests => 1 * @tests;

for my $t ( @tests ) {
  my $name = $t->{name};
  my $m    = BBC::HDS::Bootstrap::Merger->new( @{ $t->{merge} } );
  my $got  = $m->merge;
  eq_or_diff $got, $t->{expect}, "$name: merge";
}

# vim:ts=2:sw=2:et:ft=perl

