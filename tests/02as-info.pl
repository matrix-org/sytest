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
         my $localpart = "as-user-$idx";

         Future->done( ASInfo(
            $localpart,
            undef,  # user_id field will be filled in later when we know what
                    # the homeserver location actually is
            gen_token( 32 ),
            gen_token( 32 ),
            "/appservs/$idx",
            "AS-$idx",
         ));
      },
   );
} 1 .. $n_appservers;
