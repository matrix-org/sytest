test "GET /register yields a set of flows",
   requires => [qw( first_api_client )],

   provides => [qw( can_register_password_flow )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/api/v1/register",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         my $has_register_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'";

            $has_register_flow++ if
               $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.password";
         }

         $has_register_flow and
            provide can_register_password_flow => 1;

         Future->done(1);
      });
   };

# Doesn't matter what this is, but later tests will use it.
my $password = "s3kr1t";

test "POST /register can create a user",
   requires => [qw( first_api_client can_register_password_flow )],

   provides => [qw( can_register login_details )],

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type     => "m.login.password",
            user     => "01register-user",
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( user_id access_token ));

         provide can_register => 1;
         provide login_details => [ $body->{user_id}, $password ];

         Future->done( 1 );
      });
   };

sub register_new_user
{
   my ( $http, $uid, %opts ) = @_;

   $http->do_request_json(
      method => "POST",
      uri    => "/api/v1/register",

      content => {
         type     => "m.login.password",
         user     => $uid,
         password => "an0th3r s3kr1t",
      },
   )->then( sub {
      my ( $body ) = @_;
      my $access_token = $body->{access_token};

      my $user = User( $http, $body->{user_id}, $access_token, undef, undef, [], undef );

      my $f = Future->done;

      if( $opts{with_events} // 1 ) {
         $f = $f->then( sub {
            $http->do_request_json(
               method => "GET",
               uri    => "/api/v1/events",
               params => { access_token => $access_token, timeout => 0 },
            )
         })->on_done( sub {
            my ( $body ) = @_;

            $user->eventstream_token = $body->{end};
         });
      }

      return $f->then_done( $user );
   });
}

prepare "Creating test-user-creation helper function",
   requires => [qw( can_register )],

   provides => [qw( register_new_user register_new_user_without_events)],

   do => sub {
      provide register_new_user =>
         sub { register_new_user( @_[0,1] ) };

      provide register_new_user_without_events =>
         sub { register_new_user( @_[0,1], with_events => 0 ) };

      Future->done;
   };
