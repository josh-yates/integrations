# https://cloudpuzzles.net/2021/10/22/getting-secrets-from-key-vault-in-a-powershell-based-azure-function/

# WIP

# Setup

$settings = Get-Content '.\googlemymapstonotion.local.json' | ConvertFrom-Json;

# Get and parse my maps data

$myMapsLocations = Invoke-WebRequest -Uri "https://www.google.com/maps/d/kml?forcekml=1&mid=$($settings.google.myMapsId)" -Method Get |
Select-Object -ExpandProperty Content |
Select-Xml -XPath "default:kml/default:Document/default:Folder" -Namespace @{ default = "http://www.opengis.net/kml/2.2" } |
Select-Object -ExpandProperty Node |
Select-Object -Property @{label = "TypeName"; expression = { $_.name } }, @{label = "Places"; expression = { @($_.Placemark) } } |
Select-Object -Property TypeName -ExpandProperty Places |
Select-Object -Property TypeName -ExpandProperty Places |
Select-Object -Property `
    TypeName,
    name,
    @{
        label = "Coordinates";
        Expression = {
            $unparsedCoordinatesArray = (
                $_.Point |
                Select-Xml "default:coordinates" -Namespace @{ default = "http://www.opengis.net/kml/2.2" }
            ).ToString().Split(",");
            return "$($unparsedCoordinatesArray[1]),$($unparsedCoordinatesArray[0])";
        }
    }

# Notion API

$notionLocations = Invoke-WebRequest
    -Uri "https://api.notion.com/v1/databases/$($settings.notion.locations_id)/query"
    -Headers @{ Authorization = $settings.notion.key; "Notion-Version" = "2022-02-22" }
    -Method Post |
ConvertFrom-Json |
Select-Object -ExpandProperty results |
Select-Object -ExpandProperty properties |
Select-Object
    @{ label = "Name"; Expression = { $_.Name.title[0].text.content } },
    @{ label = "CountryId"; expression = { $_.Country.relation[0].id } },
    @{ label = "Coordinates"; Expression = { $_.properties.Coordinates.rich_text[0].plain_text } }

$notionCountries = Invoke-WebRequest
    -Uri "https://api.notion.com/v1/databases/$($settings.notion.countries_id)/query"
    -Headers @{ Authorization = $settings.notion.key; "Notion-Version" = "2022-02-22" }
    -Method Post |
ConvertFrom-Json |
Select-Object -ExpandProperty results |
Select-Object
    @{ label = "Id"; Expression = { $_.id } },
    @{ label = "Name"; Expression = { $_.properties.Name.title[0].text.content } }

$locationsNotInNotion = $myMapsLocations |
Where-Object {
    $searchObject = $_;
    ($notionLocations |
    Where-Object { $_.Name -eq $searchObject.Name -and $_.Coordinates -eq $searchObject.Coordinates }) -eq $null
}

$locationsNotInNotion | ForEach-Object {
    $countryName = (
        Invoke-WebRequest -Uri "https://maps.googleapis.com/maps/api/geocode/json?latlng=$($_.Coordinates)&key=$($settings.google.geocodingAPIKey)&result_type=country" |
        ConvertFrom-Json).results.formatted_address;
    
    $notionCountry = $notionCountries | Where-Object { $_.Name -eq $countryName };

    $_.CountryId = $notionCountry.Id;
}

# TODO: Push locations to Notion

# Get country / location information / maps link from places API
# Identify locations to add
# Identify locations not in maps; need flag for this
# Add notion property for coordinates, to help distinguish
# Use coordinates to identify nearby locations
# Remember coordinates in KML are swapped around, and ignore the third one
# Beans
# penguins 
# beans