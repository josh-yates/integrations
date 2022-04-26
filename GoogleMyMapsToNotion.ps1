# WIP

# Get and parse my maps data

$myMapsData = Invoke-WebRequest -Uri "https://www.google.com/maps/d/kml?forcekml=1&mid={mymaps_id}" -Method Get |
Select-Object -ExpandProperty Content |
Select-Xml -XPath "default:kml/default:Document/default:Folder" -Namespace @{ default = "http://www.opengis.net/kml/2.2" } |
Select-Object -ExpandProperty Node |
Select-Object -Property @{label = "TypeName"; expression = { $_.name } }, @{label = "Places"; expression = { @($_.Placemark) } } |
Select-Object -Property TypeName -ExpandProperty Places;

# Notion API

Invoke-WebRequest -Uri "https://api.notion.com/v1/databases/{database_id}/query" -Headers @{ Authorization = "{integration_key}"; "Notion-Version" = "2022-02-22" } -Method POST