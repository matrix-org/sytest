use JSON qw( decode_json );

# Doesn't matter what this is, but later tests will use it.
my $password = "sup3r s3kr1t";

my $registered_user_fixture = fixture(
   requires => [ $main::API_CLIENTS[0] ],

   setup => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            auth => {
               type => "m.login.dummy",
            },
            username => "02login",
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         Future->done( $body->{user_id} );
      });
   },
);

test "GET /login yields a set of flows",
   requires => [ $main::API_CLIENTS[0] ],

   proves => [qw( can_login_password_flow )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "GET",
         uri => "/r0/login",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         my $has_login_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'";

            my $stages = $flow->{stages} || [];

            $has_login_flow++ if
               $flow->{type} eq "m.login.password" or
               @$stages == 1 && $stages->[0] eq "m.login.password";
         }

         Future->done( $has_login_flow );
      });
   };

test "POST /login can log in as a user",
   requires => [ $main::API_CLIENTS[0], $registered_user_fixture,
                 qw( can_login_password_flow )],

   proves => [qw( can_login )],

   do => sub {
      my ( $http, $user_id ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.password",
            identifier => {
               type => "m.id.user",
               user => $user_id,
            },
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token home_server ));

         assert_eq( $body->{home_server}, $http->server_name,
            'Response home_server' );

         Future->done(1);
      });
   };

test "POST /login returns the same device_id as that in the request",
   requires => [ $main::API_CLIENTS[0], $registered_user_fixture,
                 qw( can_login_password_flow )],

   proves => [qw( can_login )],

   do => sub {
      my ( $http, $user_id ) = @_;

      my $device_id = "my_super_id";

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.password",
            identifier => {
               type => "m.id.user",
               user => $user_id,
            },
            password => $password,
            device_id => $device_id,
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( device_id ));

         assert_eq( $body->{device_id}, $device_id, 'device_id' );

         Future->done(1);
      });
   };

test "POST /login can log in as a user with just the local part of the id",
   requires => [ $main::API_CLIENTS[0], $registered_user_fixture,
                 qw( can_login_password_flow )],

   proves => [qw( can_login )],

   do => sub {
      my ( $http, $user_id ) = @_;

      my ( $user_localpart ) = ( $user_id =~ m/@([^:]*):/ );

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.password",
            identifier => {
               type => "m.id.user",
               user => $user_localpart,
            },
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token home_server ));

         assert_eq( $body->{home_server}, $http->server_name,
            'Response home_server' );

         Future->done(1);
      });
   };

test "POST /login as non-existing user is rejected",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_login_password_flow )],

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.password",
            identifier => {
               type => "m.id.user",
               user => "i-ought-not-to-exist",
            },
            password => "XXX",
         },
      )->main::expect_http_403;
   };

test "POST /login wrong password is rejected",
   requires => [ $main::API_CLIENTS[0], $registered_user_fixture,
                 qw( can_login_password_flow )],

   do => sub {
      my ( $http, $user_id ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.password",
            identifier => {
               type => "m.id.user",
               user => $user_id,
            },
            password => "${password}wrong",
         },
      )->main::expect_http_403->then( sub {
         my ( $resp ) = @_;

         my $body = decode_json $resp->content;

         assert_json_keys( $body, qw( errcode ));

         my $errcode = $body->{errcode};

         $errcode eq "M_FORBIDDEN" or
            die "Expected errcode to be M_FORBIDDEN but was $errcode";

         Future->done(1);
      });
   };


our @EXPORT = qw( matrix_login_again_with_user );


sub matrix_login_again_with_user
{
   my ( $user, %args ) = @_;

   $user->http->do_request_json(
      method  => "POST",
      uri     => "/r0/login",
      content  => {
         type     => "m.login.password",
         identifier => {
            type => "m.id.user",
            user => $user->user_id,
         },
         password => $user->password,
         %args,
      },
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( access_token home_server ));

      my $new_user = new_User(
         http          => $user->http,
         user_id       => $user->user_id,
         device_id     => $body->{device_id},
         password      => $user->password,
         access_token  => $body->{access_token},
      );

      Future->done( $new_user );
   });
}
