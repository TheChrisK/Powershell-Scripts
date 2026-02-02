# Connect to Microsoft Graph (with appropriate permissions)
Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All"

# Replace with your group ID
$groupId = "your-group-id-here"

# Get all user members in the group
$members = Get-MgGroupMember -GroupId $groupId -All

# Filter for only User objects (excluding service principals, devices, etc.)
$userMembers = $members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user" }

# Remove each user
foreach ($member in $userMembers) {
    Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $member.Id
    Write-Host "Removed user with ID: $($member.Id)"
}

Write-Host "All users removed from the group."
