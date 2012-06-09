# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Net-Google-SafeBrowsing2-Redis.t'

#########################

use Test::More qw(no_plan);
BEGIN { use_ok('Net::Google::SafeBrowsing2::Redis') };

require_ok( 'Net::Google::SafeBrowsing2::Redis' );

