# snippets

## make script executable

```sh
chmod +x file.sh
```

## get network (wifi/wlan) module/adapter/driver info

```sh
# simple
lspci | grep -i network

# verbose (linux)
lspci -k | grep -A 3 -i network
```

## ...

...
