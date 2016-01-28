push our @EXPORT, qw( AS_INFO );

sub gen_token
{
   my ( $length ) = @_;
   return join "", map { chr 64 + rand 63 } 1 .. $length;
}

struct ASInfo => [qw( localpart user_id as2hs_token hs2as_token path )];

our $AS_INFO = fixture(
   setup => sub {
      my $port = $HOMESERVER_PORTS[0];

      my $localpart = "as-user";

      Future->done( ASInfo(
         $localpart,
         "\@${localpart}:localhost:${port}",
         gen_token( 32 ),
         gen_token( 32 ),
         "/appserv",
      ));
   },
);
