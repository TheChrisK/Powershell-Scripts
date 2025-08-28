<#
.SYNOPSIS
    Adds missing group memberships from source Azure AD user to target user
    
.DESCRIPTION
    This script copies group memberships from a source user to a target user
    without removing any existing memberships from the target user
    
.PARAMETER SourceUser
    The UPN (User Principal Name) or ObjectId of the source user
    
.PARAMETER TargetUser
    The UPN (User Principal Name) or ObjectId of the target user
    
.PARAMETER WhatIf
    Shows what would happen without making any changes
    
.EXAMPLE
    .\Add-GroupMembership.ps1 -SourceUser "john.doe@contoso.com" -TargetUser "jane.smith@contoso.com"
    
.EXAMPLE
    .\Add-GroupMembership.ps1 -SourceUser "john.doe@contoso.com" -TargetUser "jane.smith@contoso.com" -WhatIf
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceUser,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetUser,
    
    [switch]$WhatIf
)

# Connect to Azure AD
try {
    Connect-AzureAD -ErrorAction Stop
    Write-Host "Connected to Azure AD successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Azure AD: $($_.Exception.Message)"
    exit 1
}

# Function to get user by UPN or ObjectId
function Get-AzureADUserSafe {
    param([string]$UserIdentifier)
    
    try {
        $user = Get-AzureADUser -ObjectId $UserIdentifier -ErrorAction SilentlyContinue
        if (-not $user) {
            $user = Get-AzureADUser -SearchString $UserIdentifier | Select-Object -First 1
        }
        return $user
    }
    catch {
        Write-Error "User '$UserIdentifier' not found: $($_.Exception.Message)"
        return $null
    }
}

# Get source and target users
Write-Host "Looking up source user: $SourceUser" -ForegroundColor Yellow
$sourceUserObj = Get-AzureADUserSafe -UserIdentifier $SourceUser
if (-not $sourceUserObj) { exit 1 }

Write-Host "Looking up target user: $TargetUser" -ForegroundColor Yellow
$targetUserObj = Get-AzureADUserSafe -UserIdentifier $TargetUser
if (-not $targetUserObj) { exit 1 }

Write-Host "Source user: $($sourceUserObj.UserPrincipalName)" -ForegroundColor Green
Write-Host "Target user: $($targetUserObj.UserPrincipalName)" -ForegroundColor Green

# Get source user's group memberships
Write-Host "`nRetrieving source user's group memberships..." -ForegroundColor Yellow
$sourceGroups = Get-AzureADUserMembership -ObjectId $sourceUserObj.ObjectId | Where-Object { $_.ObjectType -eq "Group" }

if (-not $sourceGroups) {
    Write-Host "Source user is not a member of any groups." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($sourceGroups.Count) groups for source user" -ForegroundColor Green

# Get target user's current group memberships
Write-Host "Retrieving target user's current group memberships..." -ForegroundColor Yellow
$targetCurrentGroups = Get-AzureADUserMembership -ObjectId $targetUserObj.ObjectId | Where-Object { $_.ObjectType -eq "Group" }

Write-Host "Target user is currently member of $($targetCurrentGroups.Count) groups" -ForegroundColor Yellow

# Identify groups that target user is NOT already a member of
$groupsToAdd = $sourceGroups | Where-Object { 
    $sourceGroup = $_
    -not ($targetCurrentGroups | Where-Object { $_.ObjectId -eq $sourceGroup.ObjectId })
}

if (-not $groupsToAdd) {
    Write-Host "`nTarget user is already a member of all the same groups as the source user." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($groupsToAdd.Count) groups to add to target user" -ForegroundColor Green

# Display groups that will be added
Write-Host "`nGroups to be added:" -ForegroundColor Yellow
foreach ($group in $groupsToAdd) {
    Write-Host "  - $($group.DisplayName)" -ForegroundColor White
}

# Confirm before proceeding (if not in WhatIf mode)
if (-not $WhatIf) {
    $confirmation = Read-Host "`nDo you want to proceed with adding these groups? (Y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

# Add target user to missing groups
$successCount = 0
$errorCount = 0

foreach ($group in $groupsToAdd) {
    try {
        if ($WhatIf) {
            Write-Host "WHATIF: Would add target user to group: $($group.DisplayName)" -ForegroundColor Cyan
            $successCount++
        }
        else {
            Write-Host "Adding target user to group: $($group.DisplayName)" -ForegroundColor Gray
            Add-AzureADGroupMember -ObjectId $group.ObjectId -RefObjectId $targetUserObj.ObjectId
            Write-Host "  ✓ Successfully added to $($group.DisplayName)" -ForegroundColor Green
            $successCount++
        }
    }
    catch {
        Write-Warning "Failed to add user to group '$($group.DisplayName)': $($_.Exception.Message)"
        $errorCount++
    }
}

# Summary
Write-Host "`n" -NoNewline
Write-Host ("="*60) -ForegroundColor Green
Write-Host "GROUP MEMBERSHIP SYNC SUMMARY" -ForegroundColor Green
Write-Host ("="*60) -ForegroundColor Green
Write-Host "Source User: $($sourceUserObj.UserPrincipalName)" -ForegroundColor White
Write-Host "Target User: $($targetUserObj.UserPrincipalName)" -ForegroundColor White
Write-Host "Source Groups Found: $($sourceGroups.Count)" -ForegroundColor White
Write-Host "Target Existing Groups: $($targetCurrentGroups.Count)" -ForegroundColor White
Write-Host "Groups to Add Identified: $($groupsToAdd.Count)" -ForegroundColor White
Write-Host "Groups Added Successfully: $successCount" -ForegroundColor Green

if ($errorCount -gt 0) {
    Write-Host "Groups Failed to Add: $errorCount" -ForegroundColor Red
}

if ($WhatIf) {
    Write-Host "`nNOTE: Operation run in WhatIf mode - no changes were made" -ForegroundColor Yellow
}
else {
    Write-Host "`nOperation completed successfully!" -ForegroundColor Green
    Write-Host "Target user now has $($targetCurrentGroups.Count + $successCount) group memberships" -ForegroundColor Green
}

# Disconnect (optional)
# Disconnect-AzureAD
