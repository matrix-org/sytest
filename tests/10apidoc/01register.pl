test "GET /register yields a set of flows",
   requires => [qw( first_http_client )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/register",
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list\n";

         my $has_register_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'\n";

            $has_register_flow++ if $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.password"
         }

         $has_register_flow and
            provide can_register_password_flow => 1;

         Future->done(1);
      });
   };

# Doesn't matter what this is, but later tests will use it.
my $password = "s3kr1t";

test "POST /register can create a user",
   requires => [qw( first_http_client can_register_password_flow )],

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/register",

         content => {
            type     => "m.login.password",
            user     => "01register-user",
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{$_} or die "Expected '$_'\n"
            for qw( user_id access_token );

         provide can_register => [ $body->{user_id}, $password ];

         Future->done( 1 );
      });
   };
