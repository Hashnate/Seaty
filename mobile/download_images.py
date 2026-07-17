import urllib.request
import json
import os

destinations = ['Colombo', 'Kandy', 'Galle', 'Ella, Sri Lanka', 'Trincomalee', 'Anuradhapura', 'Jaffna']
folder = 'assets/images/destinations'
os.makedirs(folder, exist_ok=True)

for dest in destinations:
    try:
        url = f"https://en.wikipedia.org/w/api.php?action=query&titles={urllib.parse.quote(dest)}&prop=pageimages&format=json&pithumbsize=400"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            pages = data['query']['pages']
            page = list(pages.values())[0]
            if 'thumbnail' in page:
                img_url = page['thumbnail']['source']
                clean_name = dest.split(',')[0].lower().replace(' ', '')
                file_path = os.path.join(folder, f"{clean_name}.jpg")
                print(f"Downloading {clean_name} from {img_url}")
                
                img_req = urllib.request.Request(img_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(img_req) as img_response:
                    with open(file_path, 'wb') as f:
                        f.write(img_response.read())
            else:
                print(f"No image found for {dest}")
    except Exception as e:
        print(f"Failed to process {dest}: {e}")
