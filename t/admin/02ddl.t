BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => qw( admin deploy );

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;

use DBICTest;
use DBIx::Class::_Util 'sigwarn_silencer';
use DBICTest::Util 'rm_rf';

use DBIx::Class::Admin;

# lock early
DBICTest->init_schema(no_deploy => 1, no_populate => 1);

my $db_fn = DBICTest->_sqlite_dbfilename;
my @connect_info = (
  "dbi:SQLite:$db_fn",
  undef,
  undef,
  { on_connect_do => 'PRAGMA synchronous = OFF' },
);
my $ddl_dir = "t/var/admin_ddl-$$";

{ # create the schema

#  make sure we are  clean
cleanup();


my $admin = DBIx::Class::Admin->new(
  schema_class=> "DBICTest::Schema",
  sql_dir=> $ddl_dir,
  connect_info => \@connect_info,
);
isa_ok ($admin, 'DBIx::Class::Admin', 'create the admin object');
lives_ok { $admin->create('MySQL'); } 'Can create MySQL sql';
lives_ok { $admin->create('SQLite'); } 'Can Create SQLite sql';
lives_ok {
  local $SIG{__WARN__} = sigwarn_silencer( qr/no such table.+DROP TABLE/s );
  $admin->deploy()
} 'Can Deploy schema';
}

{ # upgrade schema

cleanup();
require DBICVersion_v1;

my $admin = DBIx::Class::Admin->new(
  schema_class => 'DBICVersion::Schema',
  sql_dir =>  $ddl_dir,
  connect_info => \@connect_info,
);

my $schema = $admin->schema();

lives_ok { $admin->create($schema->storage->sqlt_type(), {add_drop_table=>0}); } 'Can create DBICVersionOrig sql in ' . $schema->storage->sqlt_type;
lives_ok { $admin->deploy(  ) } 'Can Deploy schema';

# connect to now deployed schema
lives_ok { $schema = DBICVersion::Schema->connect(@{$schema->storage->connect_info()}); } 'Connect to deployed Database';

is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema deployed and versions match');


require DBICVersion_v2;
DBICVersion::Schema->upgrade_directory (undef);  # so that we can test use of $ddl_dir

$admin = DBIx::Class::Admin->new(
  schema_class => 'DBICVersion::Schema',
  sql_dir =>  $ddl_dir,
  connect_info => \@connect_info
);

lives_ok { $admin->create($schema->storage->sqlt_type(), {}, "1.0" ); } 'Can create diff for ' . $schema->storage->sqlt_type;
{
  local $SIG{__WARN__} = sigwarn_silencer( qr/DB version .+? is lower than the schema version/ );
  lives_ok { $admin->upgrade() } 'upgrade the schema';
  dies_ok { $admin->deploy } 'cannot deploy installed schema, should upgrade instead';
}

is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema and db versions match');

}

{ # install

cleanup();

my $admin = DBIx::Class::Admin->new(
  schema_class  => 'DBICVersion::Schema',
  sql_dir      => $ddl_dir,
  _confirm    => 1,
  connect_info  => \@connect_info,
);

$admin->version("3.0");
$admin->install;
is($admin->schema->get_db_version, "3.0", 'db thinks its version 3.0');
throws_ok {
  $admin->install("4.0")
} qr/Schema already has a version. Try upgrade instead/, 'cannot install to allready existing version';

$admin->force(1);
warnings_exist ( sub {
  $admin->install("4.0")
}, qr/Forcing install may not be a good idea/, 'Force warning emitted' );
is($admin->schema->get_db_version, "4.0", 'db thinks its version 4.0');
}

sub cleanup {
  rm_rf $ddl_dir if -d $ddl_dir;
  unlink $db_fn;
}

END {
  cleanup();
}

done_testing;
