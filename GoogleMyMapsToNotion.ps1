# https://cloudpuzzles.net/2021/10/22/getting-secrets-from-key-vault-in-a-powershell-based-azure-function/

# WIP

# Setup

$settings = Get-Content '.\googlemymapstonotion.local.json' | ConvertFrom-Json;

# Get and parse my maps data

Write-Debug "Fetching my maps locations";

$myMapsLocations = Invoke-WebRequest -Uri "https://www.google.com/maps/d/kml?forcekml=1&mid=$($settings.google.myMapsId)" -Method Get |
Select-Object -ExpandProperty Content |
Select-Xml -XPath "default:kml/default:Document/default:Folder" -Namespace @{ default = "http://www.opengis.net/kml/2.2" } |
Select-Object -ExpandProperty Node |
Select-Object -Property @{label = "TypeName"; expression = { $_.name } }, @{label = "Places"; expression = { @($_.Placemark) } } |
Select-Object -Property TypeName -ExpandProperty Places |
Select-Object -Property `
    TypeName,
name,
@{
    label      = "Coordinates";
    Expression = {
        $unparsedCoordinatesArray = (
            $_.Point |
            Select-Xml "default:coordinates" -Namespace @{ default = "http://www.opengis.net/kml/2.2" }
        ).ToString().Split(",");
        return "$($unparsedCoordinatesArray[1]),$($unparsedCoordinatesArray[0])";
    }
},
@{
    label      = "CountryId";
    Expression = { $null }
}

Write-Debug "Done fetching my maps locations";

# Notion API

Write-Debug "Fetching Notion locations";

$notionLocations = Invoke-WebRequest `
    -Uri "https://api.notion.com/v1/databases/$($settings.notion.locations_id)/query" `
    -Headers @{ Authorization = $settings.notion.key; "Notion-Version" = "2022-02-22" } `
    -Method Post |
ConvertFrom-Json |
Select-Object -ExpandProperty results |
Select-Object -ExpandProperty properties |
Select-Object
@{ label = "Name"; Expression = { $_.Name.title[0].text.content } },
@{ label = "CountryId"; expression = { $_.Country.relation[0].id } },
@{ label = "Coordinates"; Expression = { $_.properties.Coordinates.rich_text[0].plain_text } }

Write-Debug "Done fetching Notion locations";

Write-Debug "Fetching Notion countries";

$notionCountries = Invoke-WebRequest `
    -Uri "https://api.notion.com/v1/databases/$($settings.notion.countries_id)/query" `
    -Headers @{ Authorization = $settings.notion.key; "Notion-Version" = "2022-02-22" } `
    -Method Post |
ConvertFrom-Json |
Select-Object -ExpandProperty results |
Select-Object -Property Id, @{ label = "Name"; Expression = { $_.properties.Name.title.plain_text } }

Write-Debug "Done fetching Notion countries";

Write-Debug "Determining locations not in Notion";

$locationsNotInNotion = $myMapsLocations |
Where-Object {
    $searchObject = $_;
    ($notionLocations |
    Where-Object { $_.Name -eq $searchObject.Name -and $_.Coordinates -eq $searchObject.Coordinates }) -eq $null
}

Write-Debug "Finished determining locations not in Notion";

Write-Debug "Fetching country for locations not in Notion";

$locationsNotInNotion | ForEach-Object {
    $countryName = (
        Invoke-WebRequest -Uri "https://maps.googleapis.com/maps/api/geocode/json?latlng=$($_.Coordinates)&key=$($settings.google.geocodingAPIKey)&result_type=country" |
        ConvertFrom-Json).results.formatted_address;
    
    $notionCountry = $notionCountries | Where-Object { $_.Name -eq $countryName };

    $_.CountryId = $notionCountry.Id;
}

Write-Debug "Done fetching country for locations not in Notion";

$locationsToPush = $locationsNotInNotion | Select-Object -Property @{
    label      = "postBody";
    Expression = {
        [PSCustomObject]@{
            parent     = [PSCustomObject]@{
                type        = "database_id";
                database_id = $settings.notion.locations_id
            };
            properties = [PSCustomObject]@{
                Name        = [PSCustomObject]@{
                    title = @(
                        [PSCustomObject]@{
                            text = [PSCustomObject]@{
                                content = $_.name
                            }
                        }
                    )
                };
                Coordinates = [PSCustomObject]@{
                    rich_text = @(
                        [PSCustomObject]@{
                            text = [PSCustomObject]@{
                                content = $_.Coordinates
                            }
                        }
                    )
                };
                Country     = [PSCustomObject]@{
                    relation = @(
                        [PSCustomObject]@{
                            id = $_.CountryId
                        }
                    )
                };
                Type        = [PSCustomObject]@{
                    select = [PSCustomObject]@{
                        name = $_.TypeName
                    }
                };
                "Maps link" = [PSCustomObject]@{
                    url = "https://www.google.com/maps/place/$($_.Coordinates)"
                }
            }
        }
    }
}

Write-Debug "Pushing locations to Notion";

$locationsToPush | ForEach-Object {
    Invoke-WebRequest `
        -Uri "https://api.notion.com/v1/pages" `
        -Headers @{ Authorization = $settings.notion.key; "Notion-Version" = "2022-02-22" } `
        -Method Post `
        -ContentType "application/json" `
        -Body ($_.postBody | ConvertTo-Json -Depth 10);
}

Write-Debug "Done pushing locations to Notion";