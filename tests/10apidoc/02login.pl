test "GET /login yields a set of flows",
   requires => [qw( first_http_client )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/login",
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list\n";

         my $has_login_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'\n";

            $has_login_flow++ if $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flows->{stages}[0] eq "m.login.password"
         }

         $has_login_flow and
            provide can_login_password_flow => 1;

         Future->done(1);
      });
   };

test "POST /login can log in as a user",
   requires => [qw( first_http_client can_register can_login_password_flow )],

   do => sub {
      my ( $http, $login_details ) = @_;
      my ( $user_id, $password ) = @$login_details;

      $http->do_request_json(
         method => "POST",
         uri    => "/login",

         content => {
            type     => "m.login.password",
            user     => $user_id,
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{access_token} or die "Expected 'access_token' in ${\pp $body}\n";

         provide can_login => [ $user_id, $body->{access_token} ];
         proivde access_token => $body->{access_token};

         Future->done(1);
      });
   };
