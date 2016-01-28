push our @EXPORT, qw( AS_INFO );

sub gen_token
{
   my ( $length ) = @_;
   return join "", map { chr 64 + rand 63 } 1 .. $length;
}

struct ASInfo => [qw( localpart user_id as2hs_token hs2as_token path id )];

my $n_appservers = 1;

our @AS_INFO = map {
   my $idx = $_;

   fixture(
      setup => sub {
         my $port = $HOMESERVER_PORTS[0];

         my $localpart = "as-user-$idx";

         Future->done( ASInfo(
            $localpart,
            "\@${localpart}:localhost:${port}",
            gen_token( 32 ),
            gen_token( 32 ),
            "/appservs/$idx",
            $idx,
         ));
      },
   );
} 1 .. $n_appservers;
