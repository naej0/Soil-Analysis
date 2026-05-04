from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from routes.admin import router as admin_router
from routes.ai import router as ai_router
from routes.assistant import router as assistant_router
from routes.climate import router as climate_router
from routes.leases import router as leases_router
from routes.productivity import router as productivity_router
from routes.recommendations import router as recommendations_router
from routes.soil import router as soil_router
from routes.users import router as users_router


app = FastAPI()

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(admin_router)
app.include_router(ai_router)
app.include_router(assistant_router)
app.include_router(climate_router)
app.include_router(leases_router)
app.include_router(productivity_router)
app.include_router(recommendations_router)
app.include_router(soil_router)
app.include_router(users_router)
