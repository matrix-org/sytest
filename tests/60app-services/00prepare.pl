use SyTest::ApplicationService;

push our @EXPORT, qw( AS_USER APPSERV );

our @AS_USER = map {
   my $AS_INFO = $_;

   fixture(
      requires => [ $main::API_CLIENTS[0], $AS_INFO ],

      setup => sub {
         my ( $http, $as_user_info ) = @_;

         Future->done( User( $http, $as_user_info->user_id,
                             undef,
                             undef, $as_user_info->as2hs_token,
                             undef, undef, undef, [], undef ) );
      },
   );
} @main::AS_INFO;

our @APPSERV = map {
   my $AS_INFO = $_;

   fixture(
      requires => [ $AS_INFO ],

      setup => sub {
         my ( $info ) = @_;

         Future->done( SyTest::ApplicationService->new(
            $info, \&main::await_http_request
         ) );
      }
   );
} @main::AS_INFO;
