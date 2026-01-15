import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ConfigModule } from '@nestjs/config';
import { S3UploadInterceptor } from './s3-upload.interceptor';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true
    })
  ],
  controllers: [AppController],
  providers: [AppService, S3UploadInterceptor],
})
export class AppModule {}
