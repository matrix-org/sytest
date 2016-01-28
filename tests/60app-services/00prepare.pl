use SyTest::ApplicationService;

push our @EXPORT, qw( AS_USER APPSERV );

our $AS_USER = fixture(
   requires => [ $main::API_CLIENTS[0], $main::AS_INFO ],

   setup => sub {
      my ( $http, $as_user_info ) = @_;

      Future->done( User( $http, $as_user_info->user_id, $as_user_info->as2hs_token,
            undef, undef, undef, [], undef ) );
   },
);

our $APPSERV = fixture(
   requires => [ $main::AS_INFO ],

   setup => sub {
      my ( $info ) = @_;

      Future->done( SyTest::ApplicationService->new(
         $info, \&main::await_http_request
      ) );
   }
);
