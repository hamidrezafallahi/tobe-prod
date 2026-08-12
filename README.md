# languageInstitute-prod — production ops only

Clone to VPS as `/opt/institute`. Application source and CI live in `LanguageInstitute-Compose`.

## Deploy
```bash
./deploy.sh frontend <git-sha>
./deploy.sh backend <git-sha>
./deploy.sh all <git-sha>
./deploy.sh rollback frontend
```

Images:
- `{DOCKER_USERNAME}/institute-frontend:<sha>`
- `{DOCKER_USERNAME}/institute-backend:<sha>`
