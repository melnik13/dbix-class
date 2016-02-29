BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;

require DBICTest::DynamicForeignCols::TestComputer;

is_deeply (
  [ DBICTest::DynamicForeignCols::TestComputer->columns ],
  [qw( test_id computer_id )],
  'All columns properly defined from DBICTest::DynamicForeignCols::Computer parentclass'
);

done_testing;
