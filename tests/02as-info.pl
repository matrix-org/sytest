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

# The actual infos
my @as_info = (
   # user_id will be filled in later once the homeserver is started

   ASInfo(
      localpart     => "as-user-1",
      user_id       => undef,
      as2hs_token   => gen_token( 32 ),
      hs2as_token   => gen_token( 32 ),
      path          => "/appservs/1",
      id            => "AS-1",
      user_regexes  => [ '@astest-.*' ],
      alias_regexes => [ '#astest-.*' ],
      protocols     => [ 'ymca' ],
   ),
);

our @AS_INFO = map {
   my $idx = $_;

   fixture(
      setup => sub { Future->done( $as_info[$idx] ) },
   );
} 0 .. $#as_info;
