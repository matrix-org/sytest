use SyTest::ApplicationService;

push our @EXPORT, qw( AS_USER APPSERV );

our @AS_USER = map {
   my $AS_INFO = $_;

   fixture(
      requires => [ $main::API_CLIENTS[0], $AS_INFO ],

      setup => sub {
         my ( $http, $as_user_info ) = @_;

         Future->done( new_User(
            http         => $http,
            user_id      => $as_user_info->user_id,
            access_token => $as_user_info->as2hs_token,
         ));
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
