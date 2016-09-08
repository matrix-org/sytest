push our @EXPORT, qw( AS_INFO );

sub gen_token
{
   my ( $length ) = @_;
   return join "", map { chr 64 + rand 63 } 1 .. $length;
}

struct ASInfo => [qw( localpart user_id as2hs_token hs2as_token path id
                      user_regexes alias_regexes protocols )],
   named_constructor => 1;

my $n_appservers = 1;

our @AS_INFO = map {
   my $idx = $_;

   fixture(
      setup => sub {
         my $localpart = "as-user-$idx";

         Future->done( ASInfo(
            localpart     => $localpart,
            user_id       => undef, # will be filled in later when we know what
                                    # the homeserver location actually is
            as2hs_token   => gen_token( 32 ),
            hs2as_token   => gen_token( 32 ),
            path          => "/appservs/$idx",
            id            => "AS-$idx",
            user_regexes  => [ '@astest-.*' ],
            alias_regexes => [ '#astest-.*' ],
            protocols     => [ 'ymca' ],
         ));
      },
   );
} 1 .. $n_appservers;
