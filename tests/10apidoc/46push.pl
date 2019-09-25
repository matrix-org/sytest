use utf8;

push our @EXPORT, qw(
   matrix_add_push_rule matrix_delete_push_rule
   matrix_get_push_rule matrix_get_push_rules
   matrix_set_push_rule_enabled
   matrix_set_push_rule_actions
);

=head2 matrix_add_push_rule

   matrix_add_push_rule( $user, $scope, $kind, $rule_id, $rule, %params )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.
rule: Hash reference for the body.
params: Extra query params for the request. E.g. "before" or "after".

=cut

sub matrix_add_push_rule
{
   my ( $user, $scope, $kind, $rule_id, $rule_body, %params ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
      params  => \%params,
      content => $rule_body,
   );
}

=head2 matrix_delete_push_rule

   matrix_delete_push_rule( $user, $scope, $kind, $rule_id )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.

=cut

sub matrix_delete_push_rule
{
   my ( $user, $scope, $kind, $rule_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
   );
}

=head2 matrix_set_push_rule_enabled

   matrix_set_push_rule_enabled( $user, $scope, $kind, $rule_id, $enabled )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.
enabled: JSON::true or JSON::false

=cut

sub matrix_set_push_rule_enabled
{
   my ( $user, $scope, $kind, $rule_id, $enabled ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id/enabled",
      content => { enabled => $enabled },
   );
}

=head2 matrix_set_push_rule_actions

   matrix_set_push_rule_actions( $user, $scope, $kind, $rule_id, $actions )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.
enabled: array of actions.

=cut

sub matrix_set_push_rule_actions
{
   my ( $user, $scope, $kind, $rule_id, $actions ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id/actions",
      content => { actions => $actions },
   );
}

=head2 matrix_get_push_rule

   my $rule = matrix_get_push_rule( $user, $scope, $kind, $rule_id )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.

Returns a hash reference with the rule body.

=cut

sub matrix_get_push_rule
{
   my ( $user, $scope, $kind, $rule_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
   );
}

=head2 matrix_get_push_rules

   my $rules = matrix_get_push_rules( $user )->get

Returns a hash reference with all the rules for the user

=cut

sub matrix_get_push_rules
{
   my ( $user ) = @_;

   # Trailing slash indicates retrieving ALL push rules for this user
   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/pushrules/",
   )->on_done( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( global ) );
   });
}
