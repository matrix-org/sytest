package SyTest::JSONSensible;

use JSON;
use Data::Dump::Filtered;

## TERRIBLY RUDE but it seems to work
package JSON::number {
   use overload '0+' => sub { ${ $_[0] } },
                fallback => 1;
   sub new {
      my ( $class, $value ) = @_;
      return bless \$value, $class;
   }

   # By this even more terrible hack we can be both a function name and a package
   sub JSON::number { JSON::number::->new( $_[0] ) }

   sub TO_JSON { 0 + ${ $_[0] } }

   Data::Dump::Filtered::add_dump_filter( sub {
      ( ref($_[1]) // '' ) eq __PACKAGE__
         ? { dump => "JSON::number(${ $_[1] })" }
         : undef;
   });
}

use constant JSON_BOOLEAN_CLASS => ref( JSON::true );

Data::Dump::Filtered::add_dump_filter( sub {
   ( ref($_[1]) // '' ) eq JSON_BOOLEAN_CLASS
      ? { dump => $_[1] ? "JSON::true" : "JSON::false" }
      : undef;
   });

1;
